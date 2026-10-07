import AppKit
import SwiftUI

/// Retained, opaque auxiliary window. Dismissing it never closes the overlay.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onCancel: () -> Void
    private let onDismiss: () -> Void

    init<Content: View>(title: String, size: NSSize, content: Content,
                       onCancel: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onDismiss = onDismiss
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.alphaValue = 1
        window.contentView = NSHostingView(rootView: content)
        window.contentMinSize = size
        window.delegate = self
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss(cancel: Bool) {
        if cancel { onCancel() }
        // Keep the controller/window alive. No close/terminate notification.
        window.orderOut(nil)
        onDismiss()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss(cancel: true)
        return false
    }
}
