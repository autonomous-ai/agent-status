import AppKit
import SwiftUI

/// Owns the optional fullscreen "Commander" dashboard window. Built imperatively
/// (rather than as a SwiftUI `Window` scene) so the window is created on demand —
/// never auto-shown at launch, which a declarative scene would do and which is
/// wrong for a menu-bar (`LSUIElement` / `.accessory`) app.
///
/// While the window is visible the app runs as `.regular` so the window can become
/// key, appear in ⌘-Tab, and go fullscreen cleanly; on close it returns to
/// `.accessory` and the app melts back into the menu bar. The shared `SessionStore`
/// keeps running either way — the menu bar still needs it.
@MainActor
final class CommanderWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private let store: SessionStore
    private let settings: Settings
    private var window: NSWindow?

    init(store: SessionStore, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    /// Open if closed, close if already on screen — the menu-bar button toggles.
    func toggle() {
        if let w = window, w.isVisible {
            w.performClose(nil)
        } else {
            show()
        }
    }

    func show() {
        if let w = window {
            becomeRegularAndActivate()
            w.makeKeyAndOrderFront(nil)
            return
        }

        let root = CommanderView()
            .environmentObject(store)
            .environmentObject(settings)

        let w = NSWindow(contentViewController: NSHostingController(rootView: root))
        w.title = "Commander"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = false
        w.setContentSize(NSSize(width: 1280, height: 820))
        w.minSize = NSSize(width: 720, height: 480)
        w.center()
        w.collectionBehavior = [.fullScreenPrimary, .managed]
        w.isReleasedWhenClosed = false   // we keep the reference and reuse it
        w.delegate = self
        window = w

        becomeRegularAndActivate()
        w.makeKeyAndOrderFront(nil)
    }

    private func becomeRegularAndActivate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Drop back out of the Dock / ⌘-Tab once the dashboard is dismissed.
        NSApp.setActivationPolicy(.accessory)
    }
}
