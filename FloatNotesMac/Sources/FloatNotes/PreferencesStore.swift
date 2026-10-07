import Foundation

struct AppPreferences: Codable, Equatable {
    var opacity = 0.5
    var systemEnabled = true
    var microphoneEnabled = false
    var microphoneID = ""
    var applicationID = ""
    var aiContext = ""

    mutating func normalize() {
        opacity = opacity.isFinite ? max(0.25, min(1, opacity)) : 0.5
    }
}

struct PreferencesStore {
    let fileURL: URL
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FloatNotes", isDirectory: true).appendingPathComponent("settings.json")
    }

    func load(legacy: UserDefaults = .standard) throws -> AppPreferences {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            var value = try JSONDecoder().decode(AppPreferences.self, from: Data(contentsOf: fileURL))
            value.normalize()
            return value
        }
        // One-time import of the previous app's preference values.
        var value = AppPreferences()
        if legacy.object(forKey: "opacity") != nil { value.opacity = legacy.double(forKey: "opacity") }
        if legacy.object(forKey: "systemEnabled") != nil { value.systemEnabled = legacy.bool(forKey: "systemEnabled") }
        value.microphoneEnabled = legacy.bool(forKey: "microphoneEnabled")
        value.microphoneID = legacy.string(forKey: "microphoneID") ?? ""
        value.applicationID = legacy.string(forKey: "applicationID") ?? ""
        value.normalize()
        return value
    }

    func save(_ preferences: AppPreferences) throws {
        var value = preferences
        value.normalize()
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic replacement completes before the Save UI dismisses.
        try data.write(to: fileURL, options: .atomic)
    }
}
