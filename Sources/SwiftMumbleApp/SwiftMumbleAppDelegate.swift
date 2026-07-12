import AppKit

@MainActor
final class SwiftMumbleAppDelegate: NSObject, NSApplicationDelegate {
    weak var session: SessionStore? {
        didSet { installTouchBar() }
    }
    private var touchBarController: SwiftMumbleTouchBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTouchBar()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) { attachTouchBarToAllWindows() }

    private func installTouchBar() {
        guard let session else { return }
        guard touchBarController?.session !== session else { return }
        let controller = SwiftMumbleTouchBarController(session: session)
        touchBarController = controller
        NSApplication.shared.touchBar = controller.makeTouchBar()
        attachTouchBarToAllWindows()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        attachTouchBar(to: window)
    }

    private func attachTouchBarToAllWindows() {
        for window in NSApplication.shared.windows { attachTouchBar(to: window) }
    }

    private func attachTouchBar(to window: NSWindow) {
        guard let touchBar = touchBarController?.makeTouchBar() else { return }
        window.touchBar = touchBar
        window.contentViewController?.touchBar = touchBar
        window.contentView?.touchBar = touchBar
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text("audio.muteToggle"), action: #selector(toggleMute), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("audio.deafenToggle"), action: #selector(toggleDeafen), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("server.disconnect"), action: #selector(disconnect), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func toggleMute() { session?.toggleMute() }
    @objc private func toggleDeafen() { session?.toggleDeafen() }
    @objc private func disconnect() { session?.disconnect() }
}
