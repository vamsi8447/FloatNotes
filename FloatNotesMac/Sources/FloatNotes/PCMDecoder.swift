import Foundation

/// Bounds-checked decoding, with no AVAudioConverter or typed pointer casts.
enum PCMDecoder {
    enum Encoding { case float32, float64, int16, int32
        var bytes: Int { switch self { case .int16: return 2; case .float64: return 8; default: return 4 } }
    }
    struct Plane { let bytes: Data; let channels: Int }

    static func mono(planes: [Plane], frames: Int, encoding: Encoding) throws -> [Int16] {
        guard frames > 0, frames <= 192_000, !planes.isEmpty, planes.count <= 32 else {
            throw AppError.message("Invalid audio buffer size.")
        }
        let channels = planes.reduce(0) { $0 + $1.channels }
        guard channels > 0, channels <= 32 else { throw AppError.message("Unsupported channel count.") }
        var sums = [Double](repeating: 0, count: frames)
        for plane in planes {
            guard plane.channels > 0, plane.channels <= 32,
                  plane.bytes.count >= frames * plane.channels * encoding.bytes else {
                throw AppError.message("An audio device returned an incomplete buffer. Stop and reconnect it.")
            }
            let bytes = [UInt8](plane.bytes)
            for frame in 0..<frames {
                for channel in 0..<plane.channels {
                    let offset = (frame * plane.channels + channel) * encoding.bytes
                    var raw: UInt64 = 0
                    for byte in 0..<encoding.bytes { raw |= UInt64(bytes[offset + byte]) << (byte * 8) }
                    let value: Double
                    switch encoding {
                    case .float32: value = Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw)))
                    case .float64: value = Double(bitPattern: raw)
                    case .int16: value = Double(Int16(bitPattern: UInt16(truncatingIfNeeded: raw))) / 32768
                    case .int32: value = Double(Int32(bitPattern: UInt32(truncatingIfNeeded: raw))) / 2147483648
                    }
                    // NaN/infinity from a changing device must never trap Int16 conversion.
                    if value.isFinite { sums[frame] += max(-1, min(1, value)) }
                }
            }
        }
        return sums.map { Int16(max(-32768, min(32767, ($0 / Double(channels) * 32768).rounded()))) }
    }
}
