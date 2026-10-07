import AppKit
import ScreenCaptureKit

@MainActor
enum ScreenshotService {
    static func captureJPEG() async throws -> Data {
        // The display containing the pointer when Capture is clicked is used.
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let wantedID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let content = try await PermissionService.shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == wantedID }) ?? content.displays.first else {
            throw AppError.message("No display is available to capture.")
        }
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw AppError.message("Open the installed FloatNotes.app, not the bare executable.")
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == bundleID }
        let ownWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID }
        let filter: SCContentFilter
        if !ownApps.isEmpty {
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        }
        let config = SCStreamConfiguration()
        let scale = min(1, 2048.0 / Double(max(display.width, display.height)))
        config.width = max(1, Int(Double(display.width) * scale))
        config.height = max(1, Int(Double(display.height) * scale))
        config.showsCursor = false
        config.capturesAudio = false
        config.captureMicrophone = false
        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
        catch { throw PermissionService.describe(error) }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let jpeg = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw AppError.message("Could not encode the captured screen.")
        }
        return jpeg
    }
}
