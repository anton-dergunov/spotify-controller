import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private var playerWindow: PlayerWindow?
    let playback = PlaybackViewModel()

    // Global monitor fires for mouse events delivered to OTHER apps, giving
    // us reliable dismissal when the user clicks anywhere outside our window.
    private var globalEventMonitor: Any?

    // Timestamp of the last time we proactively hid the window.  Used to
    // debounce the status-bar tap: if the window was just dismissed because
    // focus left it (< 150 ms ago), don't reopen on the same click.
    private var lastHideTime: TimeInterval = 0

    private var cancellables = Set<AnyCancellable>()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: 150)
        super.init()
        setupStatusItem()
        observeSpotifyRunningState()
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        let menuBarView = MenuBarItemView(onOpenWindow: { [weak self] in
            self?.togglePlayerWindow()
        })
        .environmentObject(playback)

        let hostingView = NSHostingView(rootView: menuBarView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])

        // Only intercept right-clicks via the button action mechanism.
        // Left-click events propagate normally to SwiftUI views inside hostingView.
        button.action = #selector(handleButtonAction(_:))
        button.target = self
        button.sendAction(on: [.rightMouseUp])
    }

    private func observeSpotifyRunningState() {
        playback.$isSpotifyRunning
            .sink { [weak self] running in
                // 150 pt when showing track info; 32 pt for the icon-only state.
                self?.statusItem.length = running ? 150 : 32
                if !running {
                    self?.hidePlayerWindow()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func handleButtonAction(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type == .rightMouseUp else { return }
        showContextMenu()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Quit Spotify Controller",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        // Temporarily set the menu so performClick shows it, then clear it
        // so future left-clicks don't accidentally show a menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    // Called by the tap gesture in MenuBarItemView (left-click on track info area).
    func togglePlayerWindow() {
        if let window = playerWindow, window.isVisible {
            // Clicking the status bar item while the window is open → close it.
            hidePlayerWindow()
        } else {
            // Debounce: skip if the window was just auto-dismissed (< 150 ms ago)
            // because that means this tap is the very click that defocused the window.
            let now = CACurrentMediaTime()
            guard now - lastHideTime > 0.15 else { return }
            showPlayerWindow()
        }
    }

    private func showPlayerWindow() {
        if playerWindow == nil {
            playerWindow = PlayerWindow(playback: playback)
            playerWindow?.delegate = self
        }

        guard let window = playerWindow,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonFrameInScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        let size = window.frame.size
        let x = buttonFrameInScreen.midX - size.width / 2
        // 6 pt gap between the bottom of the menu bar and the top of the window.
        let y = buttonFrameInScreen.minY - size.height - 6

        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.makeKeyAndOrderFront(nil)

        startGlobalMonitor()
    }

    private func hidePlayerWindow() {
        lastHideTime = CACurrentMediaTime()
        playerWindow?.orderOut(nil)
        stopGlobalMonitor()
    }

    // MARK: - Global event monitor

    // Fires for mouse-down events delivered to other applications, giving
    // reliable dismissal when the user clicks anywhere outside our window.
    private func startGlobalMonitor() {
        stopGlobalMonitor()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hidePlayerWindow()
            }
        }
    }

    private func stopGlobalMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }
}

extension StatusBarController: NSWindowDelegate {
    // Backup dismissal path: keyboard navigation (Cmd+Tab, Escape, etc.)
    // that shifts focus without generating a mouse-down in another app.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            hidePlayerWindow()
        }
    }
}
