import Foundation

/// Uses URLSession, so no third-party SDK or Python installation is needed.
struct OpenAIClient {
    let apiKey: String
    private let base = URL(string: "https://api.openai.com/v1/")!

    func transcribe(wav: Data, model: String) async throws -> String {
        let boundary = "FloatNotes-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(contentsOf: string.utf8) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wav)
        append("\r\n--\(boundary)--\r\n")
        let data = try await post(path: "audio/transcriptions", body: body,
                                  contentType: "multipart/form-data; boundary=\(boundary)")
        struct Transcript: Decodable { let text: String }
        return try JSONDecoder().decode(Transcript.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func answer(context: String, instruction: String, model: String) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "store": false,
            "max_output_tokens": 1000,
            "instructions": instruction,
            "input": "Recorded conversation transcript:\n\(context)"
        ]
        let data = try await post(path: "responses", body: JSONSerialization.data(withJSONObject: payload),
                                  contentType: "application/json")
        return try Self.decodeAnswer(data)
    }

    static func screenshotPayload(jpeg: Data, instruction: String, model: String) -> [String: Any] {
        [
            "model": model, "store": false, "max_output_tokens": 1000,
            "instructions": instruction,
            "input": [["role": "user", "content": [
                ["type": "input_text", "text": "Analyse this screen and respond using my saved context."],
                ["type": "input_image", "image_url": "data:image/jpeg;base64," + jpeg.base64EncodedString(), "detail": "high"]
            ]]]
        ]
    }

    func analyseScreenshot(jpeg: Data, instruction: String, model: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: Self.screenshotPayload(jpeg: jpeg, instruction: instruction, model: model))
        return try Self.decodeAnswer(try await post(path: "responses", body: body, contentType: "application/json"))
    }

    static func decodeAnswer(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Content: Decodable { let type: String; let text: String?; let refusal: String? }
                let content: [Content]?
            }
            let output: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let text = response.output.flatMap { $0.content ?? [] }.compactMap {
            $0.type == "output_text" ? $0.text : ($0.type == "refusal" ? $0.refusal : nil)
        }.joined(separator: "\n")
        guard !text.isEmpty else { throw AppError.message("The AI returned no text. Check the model name or retry.") }
        return text
    }

    private func post(path: String, body: Data, contentType: String) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("No HTTP response from OpenAI.") }
        guard (200..<300).contains(http.statusCode) else {
            // No request headers, API keys or audio bytes enter error messages.
            switch http.statusCode {
            case 401: throw AppError.message("OpenAI API key rejected (401). Check the key in Settings. This is not a macOS permission error.")
            case 403: throw AppError.message("OpenAI API access denied (403). Check your API project and model access. macOS screen/microphone settings do not control this permission.")
            case 429: throw AppError.message("API limit or quota reached (429). Check API billing and rate limits.")
            case 400, 404: throw AppError.message("Request/model rejected (\(http.statusCode)). Check model names and account access.")
            default: throw AppError.message("OpenAI request failed (HTTP \(http.statusCode)). Retry when connectivity/service recovers.")
            }
        }
        return data
    }
}
