import AppKit
import AVFoundation
import Combine
import ScreenCaptureKit

@MainActor
final class AppModel: ObservableObject {
    enum Phase { case idle, starting, listening, stopping, answering, capturing }
    struct AudioApp: Identifiable { let id: String; let name: String }
    @Published var apiKey = ""
    @Published var systemEnabled = true
    @Published var microphoneEnabled = false
    @Published var microphoneID = ""
    @Published var applicationID = ""
    @Published var microphones: [AVCaptureDevice] = []
    @Published var audioApps: [AudioApp] = []
    @Published var opacity = 0.5
    @Published private(set) var aiContext = ""
    @Published var editorIsOpen = false
    @Published private(set) var contextMessage = ""
    var showSettings: (() -> Void)?
    var showContext: (() -> Void)?
    @Published private(set) var phase = Phase.idle
    @Published private(set) var transcript: [TranscriptLine] = []
    @Published private(set) var answer = ""
    @Published private(set) var status = "Click Listen to begin."
    @Published private(set) var errorMessage = ""
    @Published private(set) var settingsMessage = ""
    var setWindowOpacity: ((Double) -> Void)?
    var canConfigure: Bool { phase == .idle }
    var isListening: Bool { phase == .listening }
    var isBusy: Bool { phase != .idle && phase != .listening }
    var transcriptText: String {
        transcript.map { "[\($0.source.rawValue)] \($0.text)" }.joined(separator: "\n\n")
    }
    private let preferencesStore: PreferencesStore
    private var savedPreferences = AppPreferences()
    private var savedAPIKey = ""
    private var sessionPrompt = ""

    init(preferencesStore: PreferencesStore = PreferencesStore()) {
        self.preferencesStore = preferencesStore
    }

    private var capture: CaptureService?
    private var transcriptionTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var transcriptionFailed = false
    private var captureFailed = false

    func loadSettings() {
        do { apiKey = try KeychainStore.load() }
        catch { settingsMessage = error.localizedDescription }
        savedAPIKey = apiKey
        do {
            savedPreferences = try preferencesStore.load()
            apply(savedPreferences)
        } catch { errorMessage = "Could not read saved settings: \(error.localizedDescription)" }
    }

    private func apply(_ value: AppPreferences) {
        opacity = value.opacity
        systemEnabled = value.systemEnabled
        microphoneEnabled = value.microphoneEnabled
        microphoneID = value.microphoneID
        applicationID = value.applicationID
        aiContext = value.aiContext
        setWindowOpacity?(opacity)
    }

    func cancelSettings() {
        apply(savedPreferences)
        apiKey = savedAPIKey
        settingsMessage = ""
    }

    func saveContext(_ text: String) -> Bool {
        guard canConfigure else { return false }
        var updated = savedPreferences
        updated.aiContext = text
        do {
            try preferencesStore.save(updated)
            savedPreferences = updated
            aiContext = text
            contextMessage = ""
            return true
        } catch { contextMessage = "Could not save context: \(error.localizedDescription)"; return false }
    }

    func unlockSavedKey() {
        do {
            apiKey = try KeychainStore.load(allowInteraction: true)
            savedAPIKey = apiKey
            settingsMessage = apiKey.isEmpty ? "No saved API key. Paste your key above." : "Saved key loaded."
        } catch { settingsMessage = error.localizedDescription }
    }

    func refreshMicrophones() {
        // Enumeration only: opening Settings never starts an audio stream.
        microphones = AVCaptureDevice.devices(for: .audio)
        if !microphoneID.isEmpty && !microphones.contains(where: { $0.uniqueID == microphoneID }) { microphoneID = "" }
    }

    func refreshApps() async {
        do {
            let content = try await PermissionService.shareableContent()
            var seen = Set<String>()
            audioApps = content.applications.compactMap { app in
                guard !app.bundleIdentifier.isEmpty, app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      seen.insert(app.bundleIdentifier).inserted else { return nil }
                return AudioApp(id: app.bundleIdentifier, name: app.applicationName)
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !applicationID.isEmpty && !audioApps.contains(where: { $0.id == applicationID }) { applicationID = "" }
            settingsMessage = "Audio apps refreshed."
        } catch { settingsMessage = "Cannot list apps: \(error.localizedDescription)" }
    }

    func saveSettings() -> Bool {
        guard canConfigure else { return false }
        var updated = savedPreferences
        updated.opacity = opacity
        updated.systemEnabled = systemEnabled
        updated.microphoneEnabled = microphoneEnabled
        updated.microphoneID = microphoneID
        updated.applicationID = applicationID
        updated.normalize()
        do {
            // Persist the display/audio choices independently of Keychain.
            try preferencesStore.save(updated)
            savedPreferences = updated
            opacity = updated.opacity
            setWindowOpacity?(opacity)
        } catch {
            settingsMessage = "Could not save settings: \(error.localizedDescription)"
            return false
        }
        do {
            apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            // Adjusting opacity must not rewrite an unchanged API key.
            if apiKey != savedAPIKey {
                if apiKey.isEmpty { try KeychainStore.delete() } else { try KeychainStore.save(apiKey) }
                savedAPIKey = apiKey
            }
            settingsMessage = "Saved."
            return true
        } catch {
            settingsMessage = "Display/audio settings saved; API key could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func listen() async {
        guard phase == .idle, capture == nil, !editorIsOpen else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { errorMessage = "Open Settings and enter your OpenAI API key."; return }
        guard systemEnabled || microphoneEnabled else { errorMessage = "Choose computer audio or microphone in Settings."; return }
        sessionPrompt = ResponsePrompt.instructions(userContext: aiContext)
        phase = .starting; status = "Starting audio…"; errorMessage = ""
        transcript.removeAll(); answer = ""; transcriptionFailed = false; captureFailed = false
        sessionID = UUID()
        let id = sessionID
        let service = CaptureService { [weak self] message in
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                self.captureFailed = true
                self.errorMessage = message
                if self.phase == .listening { await self.stopAndAnswer() }
            }
        }
        capture = service
        let client = OpenAIClient(apiKey: key)
        // A single consumer preserves order and finishes only after final chunks.
        transcriptionTask = Task { [weak self] in
            for await chunk in service.chunks {
                guard let self, self.sessionID == id, !Task.isCancelled else { return }
                if self.transcriptionFailed { continue }
                do {
                    let text = try await client.transcribe(wav: chunk.wav, model: Settings.defaultTranscriptionModel)
                    guard self.sessionID == id, !Task.isCancelled else { return }
                    if !text.isEmpty {
                        self.transcript.append(TranscriptLine(time: chunk.startedAt, source: chunk.source, text: text))
                        self.transcript.sort { $0.time < $1.time }
                    }
                } catch {
                    guard !Task.isCancelled, self.sessionID == id else { return }
                    self.transcriptionFailed = true
                    self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                    // Schedule outside this consumer: Stop waits for its completion.
                    if self.phase == .listening { Task { await self.stopAndAnswer() } }
                }
            }
        }
        do {
            try await service.start(system: systemEnabled, microphone: microphoneEnabled,
                                    microphoneID: microphoneID, applicationID: applicationID)
            phase = .listening; status = "Listening… click Stop for a text answer."
            if captureFailed || transcriptionFailed { await stopAndAnswer() }
        } catch {
            transcriptionTask?.cancel(); transcriptionTask = nil
            capture = nil; phase = .idle
            errorMessage = "Could not start: \(error.localizedDescription)"
            status = "Stopped. Check Settings and macOS permissions."
        }
    }

    func captureScreen() async {
        guard phase == .idle, !editorIsOpen else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { errorMessage = "Open Settings and enter or unlock your OpenAI API key."; return }
        let prompt = ResponsePrompt.instructions(userContext: aiContext, inputKind: .screen)
        phase = .capturing; status = "Capturing this display…"; errorMessage = ""
        answer = ""
        defer { phase = .idle }
        do {
            let jpeg = try await ScreenshotService.captureJPEG()
            phase = .answering
            status = "Screenshot captured. Analysing with AI…"
            answer = try await OpenAIClient(apiKey: key).analyseScreenshot(jpeg: jpeg, instruction: prompt,
                                                                          model: Settings.defaultAnswerModel)
            status = "Screen analysis complete."
        } catch { errorMessage = error.localizedDescription; status = "Capture/analysis could not finish." }
    }

    func stopAndAnswer() async {
        guard phase == .listening else { return }
        phase = .stopping; status = "Stopping audio…"
        do { try await capture?.stop() }
        catch {
            phase = .listening
            errorMessage = "Could not stop audio: \(error.localizedDescription). Retry Stop or quit the app."
            status = "Capture may still be active."
            return
        }
        capture = nil
        status = "Audio stopped. Finishing transcription…"
        await transcriptionTask?.value
        transcriptionTask = nil
        guard !transcriptionFailed, !captureFailed else {
            phase = .idle; status = "Stopped after an audio/API error. Transcript may be incomplete."
            return
        }
        guard !transcript.isEmpty else { phase = .idle; status = "No speech detected. Click Listen to try again."; return }
        phase = .answering; status = "Writing a text answer…"
        do {
            answer = try await OpenAIClient(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)).answer(
                context: transcriptText,
                instruction: sessionPrompt,
                model: Settings.defaultAnswerModel)
            status = "Done. Click Listen for a new recording."
        } catch { errorMessage = error.localizedDescription; status = "Audio stopped. Could not generate the answer." }
        phase = .idle
    }
}
