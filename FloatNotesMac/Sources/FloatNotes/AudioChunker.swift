import AudioToolbox
import CoreMedia
import Foundation

/// Called only on CaptureService's serial sample queue.
final class AudioChunker {
    private let source: AudioSource
    private let emit: (AudioChunk) -> Void
    private var pcm = Data()
    private var sampleRate: Double = 0
    private var startedAt = Date()
    private var hasSignal = false

    init(source: AudioSource, emit: @escaping (AudioChunk) -> Void) {
        self.source = source; self.emit = emit
    }

    func append(_ sample: CMSampleBuffer) throws {
        guard sample.isValid, CMSampleBufferDataIsReady(sample),
              let description = CMSampleBufferGetFormatDescription(sample),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0 else { return }
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate.isFinite, (8000...192000).contains(format.mSampleRate),
              format.mChannelsPerFrame > 0, format.mChannelsPerFrame <= 32,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mFormatFlags & kAudioFormatFlagIsAlignedHigh == 0 else {
            throw AppError.message("Unsupported audio format. Try the Mac's built-in microphone.")
        }
        let encoding: PCMDecoder.Encoding
        let floating = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let signed = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        switch (floating, signed, format.mBitsPerChannel) {
        case (true, _, 32): encoding = .float32
        case (true, _, 64): encoding = .float64
        case (false, true, 16): encoding = .int16
        case (false, true, 32): encoding = .int32
        default: throw AppError.message("Unsupported PCM format. Choose another microphone in Settings.")
        }
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let expectedStride = encoding.bytes * (planar ? 1 : Int(format.mChannelsPerFrame))
        guard Int(format.mBytesPerFrame) == expectedStride else {
            throw AppError.message("Padded audio formats are not supported. Choose another input.")
        }
        var needed = 0
        var retainedBlock: CMBlockBuffer?
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sample, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, blockBufferOut: &retainedBlock)
        guard needed >= MemoryLayout<AudioBufferList>.size, needed <= 65536 else {
            throw AppError.message("Invalid audio buffer layout.")
        }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { storage.deallocate() }
        let listPointer = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sample, bufferListSizeNeededOut: nil, bufferListOut: listPointer, bufferListSize: needed,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, blockBufferOut: &retainedBlock)
        guard result == noErr else { throw AppError.message("Audio buffer read failed (\(result)).") }
        let count = Int(listPointer.pointee.mNumberBuffers)
        let requiredSize = MemoryLayout<AudioBufferList>.size + max(0, count - 1) * MemoryLayout<AudioBuffer>.stride
        guard count > 0, count <= 32, requiredSize <= needed else {
            throw AppError.message("Invalid audio channel layout.")
        }
        let planes: [PCMDecoder.Plane] = try withExtendedLifetime(retainedBlock) {
            try UnsafeMutableAudioBufferListPointer(listPointer).map { buffer in
                guard let data = buffer.mData, buffer.mDataByteSize <= 32 * 192000 * 8 else {
                    throw AppError.message("The audio device returned an invalid buffer.")
                }
                return PCMDecoder.Plane(bytes: Data(bytes: data, count: Int(buffer.mDataByteSize)),
                                        channels: Int(buffer.mNumberChannels))
            }
        }
        let samples = try PCMDecoder.mono(planes: planes, frames: frames, encoding: encoding)
        if sampleRate != format.mSampleRate { flush(); sampleRate = format.mSampleRate }
        if pcm.isEmpty { startedAt = Date() }
        for sample in samples {
            if sample != 0 { hasSignal = true }
            let raw = UInt16(bitPattern: sample)
            pcm.append(UInt8(truncatingIfNeeded: raw))
            pcm.append(UInt8(truncatingIfNeeded: raw >> 8))
        }
        if Double(pcm.count / 2) >= sampleRate * Settings.chunkSeconds { flush() }
    }

    /// Also called after capture stops, to keep the last partial sentence.
    func flush() {
        defer { pcm.removeAll(keepingCapacity: true); hasSignal = false }
        guard !pcm.isEmpty, sampleRate > 0, hasSignal else { return }
        emit(AudioChunk(source: source, startedAt: startedAt,
                        wav: WAVEncoder.encode(pcm: pcm, sampleRate: UInt32(sampleRate))))
    }
}
