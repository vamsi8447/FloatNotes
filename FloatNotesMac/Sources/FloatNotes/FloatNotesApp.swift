import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: OverlayPanel?
    private let model = AppModel()
    private var editor: EditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let root = NSMenuItem()
        let items = NSMenu()
        items.addItem(withTitle: "Quit FloatNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = items; appMenu.addItem(root)
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = editMenu; appMenu.addItem(editRoot)
        NSApp.mainMenu = appMenu

        let panel = OverlayPanel(contentRect: NSRect(x: 100, y: 100, width: 440, height: 420),
                                 styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                 backing: .buffered, defer: false)
        panel.delegate = self
        panel.title = "FloatNotes 0.4"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        model.setWindowOpacity = { [weak panel] opacity in panel?.alphaValue = opacity }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.showContext = { [weak self] in self?.openContext() }
        model.loadSettings()
        panel.alphaValue = model.opacity
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        panel.contentMinSize = NSSize(width: 300, height: 240)
        // Do not set sharingType = .none: it does not reliably exclude the
        // window from ScreenCaptureKit-based screen sharing on modern macOS.
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        if model.apiKey.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
    }

    private func openSettings() {
        guard model.canConfigure, !model.editorIsOpen else { return }
        model.editorIsOpen = true
        editor = EditorWindowController(title: "FloatNotes Settings", size: NSSize(width: 490, height: 520),
            content: SettingsView(model: model,
                dismiss: { [weak self] in self?.editor?.dismiss(cancel: false) },
                cancel: { [weak self] in self?.editor?.dismiss(cancel: true) }),
            onCancel: { [weak self] in self?.model.cancelSettings() },
            onDismiss: { [weak self] in self?.restoreOverlay() })
        editor?.show()
    }

    private func openContext() {
        guard model.canConfigure, !model.editorIsOpen else { return }
        model.editorIsOpen = true
        editor = EditorWindowController(title: "FloatNotes Context", size: NSSize(width: 560, height: 440),
            content: ContextView(model: model, dismiss: { [weak self] in self?.editor?.dismiss(cancel: false) }),
            onCancel: {}, onDismiss: { [weak self] in self?.restoreOverlay() })
        editor?.show()
    }

    private func restoreOverlay() {
        model.editorIsOpen = false
        panel?.alphaValue = model.opacity
        panel?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Only the main overlay's close button quits. Editor windows have
        // their own delegate and only hide themselves.
        if sender === panel { NSApp.terminate(nil); return false }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.makeKeyAndOrderFront(nil)
        return true
    }
}

@main
enum FloatNotesApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
