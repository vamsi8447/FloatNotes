import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
enum PermissionService {
    static func requireMicrophone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
            throw AppError.message("macOS microphone permission was not granted. Enable FloatNotes in Privacy & Security → Microphone, then quit and reopen this installed copy.")
        case .denied:
            throw AppError.message("macOS microphone access is denied for this app build. Enable the installed FloatNotes in Privacy & Security → Microphone and reopen it. A previously allowed, differently signed copy may have a separate permission record.")
        case .restricted:
            throw AppError.message("Microphone access is restricted by macOS or device management.")
        @unknown default:
            throw AppError.message("macOS returned an unknown microphone permission state.")
        }
    }

    static func shareableContent() async throws -> SCShareableContent {
        // Called only after Listen/Capture or explicit Refresh in Settings.
        // Do not reject solely on a cached preflight result; ask the actual API.
        do { return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { throw describe(error) }
    }

    static func describe(_ error: Error) -> AppError {
        let native = error as NSError
        // SCStreamError.userDeclined: do not label unrelated errors as denial.
        if native.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain", native.code == -3801 {
            return .message("macOS denied Screen & System Audio Recording for this app build. Enable the installed FloatNotes in Privacy & Security, quit it fully, and reopen it. If already enabled, see README → Permission repair. (ScreenCaptureKit -3801)")
        }
        return .message("macOS capture failed [\(native.domain) \(native.code)]: \(native.localizedDescription)")
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
