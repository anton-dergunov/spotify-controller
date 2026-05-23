import AppKit
import SwiftUI

// Hosts SettingsView in a standard titled NSWindow.
// Persisted across opens (`isReleasedWhenClosed = false`) so subsequent calls
// just bring the existing window to the front.
@MainActor
final class SettingsWindowController: NSObject {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func show(authService: SpotifyAuthService) {
        // Ensure the app is foregrounded so the window receives clicks.
        // (Our app is .accessory; without activating, the window can appear
        // but not capture key events properly.)
        NSApp.activate(ignoringOtherApps: true)

        if let win = window {
            win.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView()
            .environmentObject(authService)
            .environmentObject(MenuBarSettings.shared)
            .environmentObject(HotkeySettings.shared)

        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title              = "Harmonic Settings"
        win.styleMask          = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.fullScreenAuxiliary]
        win.delegate           = self
        win.setContentSize(NSSize(width: 580, height: 500))
        win.minSize            = NSSize(width: 480, height: 380)
        win.center()
        win.makeKeyAndOrderFront(nil)

        self.window = win
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindowController: NSWindowDelegate {
    // No-op for now — `isReleasedWhenClosed = false` keeps the window object alive
    // so the next show() call just re-orders it to front with state preserved.
}
