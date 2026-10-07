import Foundation

enum AudioSource: String, Sendable { case system = "System audio", microphone = "Microphone" }

struct AudioChunk: Sendable {
    let source: AudioSource
    let startedAt: Date
    let wav: Data
}

struct TranscriptLine: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let source: AudioSource
    let text: String
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum Settings {
    static let chunkSeconds = 4.0
    static let defaultTranscriptionModel = "gpt-4o-mini-transcribe"
    static let defaultAnswerModel = "gpt-4.1-mini"
}
