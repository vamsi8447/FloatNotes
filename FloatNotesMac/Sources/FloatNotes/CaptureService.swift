import AVFoundation
import ScreenCaptureKit

final class CaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation
    @MainActor private var stream: SCStream?
    private let queue = DispatchQueue(label: "FloatNotes.audio", qos: .userInitiated)
    private var chunkers: [AudioSource: AudioChunker] = [:]
    private var finished = false // access only on queue
    private var reportedError = false // access only on queue
    private let onError: (String) -> Void

    init(onError: @escaping (String) -> Void) {
        let pair = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingOldest(16))
        chunks = pair.stream; continuation = pair.continuation
        self.onError = onError
        super.init()
        for source in [AudioSource.system, .microphone] {
            chunkers[source] = AudioChunker(source: source) { [weak self] chunk in
                guard let self else { return }
                if case .dropped = self.continuation.yield(chunk) {
                    self.report("Transcription cannot keep up. Capture has been stopped; some audio could not be transcribed.")
                }
            }
        }
    }

    @MainActor func start(system: Bool, microphone: Bool, microphoneID: String, applicationID: String) async throws {
        if microphone {
            try await PermissionService.requireMicrophone()
            if !microphoneID.isEmpty {
                guard AVCaptureDevice.devices(for: .audio).contains(where: { $0.uniqueID == microphoneID }) else {
                    throw AppError.message("The selected microphone is disconnected. Choose System default in Settings.")
                }
            }
        }
        let content = try await PermissionService.shareableContent()
        guard let display = content.displays.first else { throw AppError.message("No display is available.") }
        let filter: SCContentFilter
        if system && !applicationID.isEmpty {
            let selected = content.applications.filter { $0.bundleIdentifier == applicationID }
            guard !selected.isEmpty else { throw AppError.message("The selected audio app is closed. Open it or choose All apps.") }
            filter = SCContentFilter(display: display, including: selected, exceptingWindows: [])
        } else {
            let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        }
        let config = SCStreamConfiguration()
        config.width = 64; config.height = 64
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3; config.showsCursor = false
        config.capturesAudio = system; config.sampleRate = 48000; config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = microphone
        config.microphoneCaptureDeviceID = microphoneID.isEmpty ? nil : microphoneID
        let candidate = SCStream(filter: filter, configuration: config, delegate: self)
        try candidate.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if system { try candidate.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if microphone { try candidate.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        stream = candidate
        do { try await candidate.startCapture() }
        catch { stream = nil; await finish(); throw PermissionService.describe(error) }
    }

    @MainActor func stop() async throws {
        if let current = stream {
            try await current.stopCapture()
            stream = nil
        }
        await finish()
    }

    private func finish() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if !finished {
                    finished = true
                    for source in [AudioSource.system, .microphone] { chunkers[source]?.flush() }
                    continuation.finish()
                }
                done.resume()
            }
        }
    }

    private func report(_ message: String) {
        guard !reportedError else { return }
        reportedError = true
        onError(message)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard !finished else { return }
        let source: AudioSource
        switch outputType { case .audio: source = .system; case .microphone: source = .microphone; default: return }
        do { try chunkers[source]?.append(sampleBuffer) }
        catch { report(error.localizedDescription) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.stream = nil
            onError("Audio capture interrupted: \(error.localizedDescription)")
            await finish()
        }
    }
}
