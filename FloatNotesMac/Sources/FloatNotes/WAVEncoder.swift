import Foundation

enum WAVEncoder {
    /// Input: little-endian, signed 16-bit, mono PCM. No file is written.
    static func encode(pcm: Data, sampleRate: UInt32) -> Data {
        precondition(pcm.count <= Int(UInt32.max) - 36 && pcm.count % 2 == 0)
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); u32(UInt32(pcm.count) + 36); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        text("data"); u32(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}
