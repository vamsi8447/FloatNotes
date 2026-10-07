import XCTest
@testable import FloatNotes

final class CoreTests: XCTestCase {
    func testWAVHeaderAndPayload() {
        let pcm = Data([0, 0, 255, 127, 0, 128])
        let wav = WAVEncoder.encode(pcm: pcm, sampleRate: 48000)
        XCTAssertEqual(wav.count, 50)
        XCTAssertEqual(String(data: wav[0..<4], encoding: .utf8), "RIFF")
        XCTAssertEqual(Array(wav[4..<8]), [42, 0, 0, 0])
        XCTAssertEqual(Array(wav[24..<28]), [128, 187, 0, 0])
        XCTAssertEqual(Array(wav[40..<44]), [6, 0, 0, 0])
        XCTAssertEqual(Data(wav.suffix(6)), pcm)
    }

    func testResponseIgnoresReasoningItemsAndCombinesText() throws {
        let json = #"{"output":[{"type":"reasoning"},{"content":[{"type":"output_text","text":"One"},{"type":"output_text","text":"Two"}]}]}"#
        XCTAssertEqual(try OpenAIClient.decodeAnswer(Data(json.utf8)), "One\nTwo")
    }

    func testRefusalIsDisplayed() throws {
        let json = #"{"output":[{"content":[{"type":"refusal","refusal":"Cannot answer"}]}]}"#
        XCTAssertEqual(try OpenAIClient.decodeAnswer(Data(json.utf8)), "Cannot answer")
    }

    func testEmptyAnswerThrows() {
        XCTAssertThrowsError(try OpenAIClient.decodeAnswer(Data(#"{"output":[]}"#.utf8)))
    }
}

final class PCMDecoderTests: XCTestCase {
    private func floats(_ values: [Float]) -> Data {
        var result = Data()
        for value in values {
            let bits = value.bitPattern
            for byte in 0..<4 { result.append(UInt8(truncatingIfNeeded: bits >> (byte * 8))) }
        }
        return result
    }

    func testPlanarAndInterleavedStereoProduceSameMono() throws {
        let interleaved = try PCMDecoder.mono(
            planes: [.init(bytes: floats([0.5, -0.5, 0.25, 0.75]), channels: 2)], frames: 2, encoding: .float32)
        let planar = try PCMDecoder.mono(
            planes: [.init(bytes: floats([0.5, 0.25]), channels: 1),
                     .init(bytes: floats([-0.5, 0.75]), channels: 1)], frames: 2, encoding: .float32)
        XCTAssertEqual(interleaved, [0, 16384])
        XCTAssertEqual(planar, interleaved)
    }

    func testNonFiniteAndClippingNeverTrap() throws {
        let decoded = try PCMDecoder.mono(
            planes: [.init(bytes: floats([.nan, .infinity, -.infinity, 2, -2]), channels: 1)],
            frames: 5, encoding: .float32)
        XCTAssertEqual(decoded, [0, 0, 0, 32767, -32768])
    }

    func testTruncatedBufferThrowsBeforeReading() {
        XCTAssertThrowsError(try PCMDecoder.mono(
            planes: [.init(bytes: Data([1, 2]), channels: 2)], frames: 100, encoding: .float32))
    }

    func testMonoIntegerSamplesArePreserved() throws {
        let decoded = try PCMDecoder.mono(
            planes: [.init(bytes: Data([0, 128, 255, 127, 0, 0]), channels: 1)], frames: 3, encoding: .int16)
        XCTAssertEqual(decoded, [-32768, 32767, 0])
    }
}

final class PreferencesAndContextTests: XCTestCase {
    func testOpacityAndMultilineContextSurviveNewStoreInstance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        var preferences = AppPreferences()
        preferences.opacity = 0.73
        preferences.aiContext = "Act as a data engineering coach.\nUse simple English.\nతెలుగు"
        try PreferencesStore(fileURL: url).save(preferences)
        let restored = try PreferencesStore(fileURL: url).load()
        XCTAssertEqual(restored.opacity, 0.73)
        XCTAssertEqual(restored.aiContext, preferences.aiContext)
        XCTAssertEqual(restored, preferences)
    }

    func testContextUpdatePreservesOpacityAndAudioSources() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PreferencesStore(fileURL: directory.appendingPathComponent("settings.json"))
        var preferences = AppPreferences()
        preferences.opacity = 0.9
        preferences.microphoneID = "test-device"
        preferences.microphoneEnabled = true
        try store.save(preferences)
        var updated = try store.load()
        updated.aiContext = "Use brief examples."
        try store.save(updated)
        let restored = try store.load()
        XCTAssertEqual(restored.opacity, 0.9)
        XCTAssertEqual(restored.microphoneID, "test-device")
        XCTAssertTrue(restored.microphoneEnabled)
    }

    func testUnwritableDestinationReportsFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blocker)
        let store = PreferencesStore(fileURL: blocker.appendingPathComponent("settings.json"))
        XCTAssertThrowsError(try store.save(AppPreferences()))
    }

    func testCustomRoleAppearsInInstructionsWithoutBeingRewritten() {
        let role = "Act as a Spark architect.\nRespond in three bullet points."
        let instructions = ResponsePrompt.instructions(userContext: role)
        XCTAssertTrue(instructions.contains(role))
        XCTAssertTrue(instructions.contains("text-only"))
        XCTAssertFalse(instructions.contains("Be direct and concise."))
    }

    func testBlankContextKeepsDefaultBehaviour() {
        let instructions = ResponsePrompt.instructions(userContext: " \n ")
        XCTAssertTrue(instructions.contains("Be direct and concise."))
        XCTAssertFalse(instructions.contains("User's saved role"))
    }
}

final class ScreenAnalysisTests: XCTestCase {
    func testScreenshotRequestContainsImageContextAndNoAudioOutput() throws {
        let image = Data([255, 216, 255])
        let body = OpenAIClient.screenshotPayload(jpeg: image, instruction: "Explain SQL briefly.", model: "gpt-4.1-mini")
        let data = try JSONSerialization.data(withJSONObject: body)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(decoded["instructions"] as? String, "Explain SQL briefly.")
        XCTAssertEqual(decoded["store"] as? Bool, false)
        let input = try XCTUnwrap(decoded["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content[1]["type"] as? String, "input_image")
        XCTAssertEqual(content[1]["image_url"] as? String, "data:image/jpeg;base64," + image.base64EncodedString())
        XCTAssertNil(decoded["audio"])
    }

    func testScreenInstructionsPreserveUserContext() {
        let prompt = ResponsePrompt.instructions(userContext: "Act as a database architect.", inputKind: .screen)
        XCTAssertTrue(prompt.contains("screenshot"))
        XCTAssertTrue(prompt.contains("Act as a database architect."))
        XCTAssertFalse(prompt.contains("recorded transcript"))
    }
}
