import AppKit
import TouchBarHelper

@MainActor
final class SwiftMumbleAppDelegate: NSObject, NSApplicationDelegate {
    weak var session: SessionStore? {
        didSet { installTouchBar() }
    }
    private var touchBarController: SwiftMumbleTouchBarController?
    private var systemTouchBarController: SwiftMumbleSystemTouchBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTouchBar()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(touchBarControlStripPreferenceChanged),
            name: .touchBarControlStripPreferenceChanged,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        systemTouchBarController?.removeFromControlStrip()
        NSApplication.shared.touchBar = touchBarController?.makeTouchBar()
        attachTouchBarToAllWindows()
    }

    func applicationDidResignActive(_ notification: Notification) {
        updateControlStripPresentation()
    }

    private func installTouchBar() {
        guard let session else { return }
        guard touchBarController?.session !== session else { return }
        let controller = SwiftMumbleTouchBarController(session: session)
        touchBarController = controller
        NSApplication.shared.touchBar = controller.makeTouchBar()
        systemTouchBarController?.removeFromControlStrip()
        systemTouchBarController = SwiftMumbleSystemTouchBarController(
            touchBar: controller.makeTouchBar(),
            itemProvider: controller
        )
        systemTouchBarController?.removeFromControlStrip()
        attachTouchBarToAllWindows()
        updateControlStripPresentation()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        attachTouchBar(to: window)
    }

    @objc private func touchBarControlStripPreferenceChanged() {
        updateControlStripPresentation()
    }

    private func updateControlStripPresentation() {
        guard let session, session.touchBarControlStripEnabled, !NSApp.isActive else {
            systemTouchBarController?.removeFromControlStrip()
            if NSApp.isActive { NSApplication.shared.touchBar = touchBarController?.makeTouchBar() }
            return
        }
        NSApplication.shared.touchBar = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let self, self.session?.touchBarControlStripEnabled == true, !NSApp.isActive else { return }
            self.systemTouchBarController?.showInControlStrip()
        }
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

@MainActor
private final class SwiftMumbleSystemTouchBarController: TouchBarSystemModalController, @unchecked Sendable {
    private let hostedTouchBar: NSTouchBar
    private let itemProvider: SwiftMumbleTouchBarController

    init(touchBar: NSTouchBar, itemProvider: SwiftMumbleTouchBarController) {
        hostedTouchBar = touchBar
        self.itemProvider = itemProvider
        super.init()
    }

    override func loadTouchBar() {
        touchBar = hostedTouchBar
    }

    nonisolated override func touchBarDidLoad() {
        MainActor.assumeIsolated {
            let item = NSCustomTouchBarItem(identifier: .swiftMumbleSystemTray)
            let title = "SwiftMumble"
            let button = NSButton(
                image: NSImage(
                    systemSymbolName: "waveform.badge.mic",
                    accessibilityDescription: title
                ) ?? NSImage(),
                target: self,
                action: #selector(present)
            )
            button.toolTip = title
            item.view = button
            systemTrayItem = item
        }
    }

    nonisolated func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        MainActor.assumeIsolated {
            itemProvider.touchBar(touchBar, makeItemForIdentifier: identifier)
        }
    }
}

extension Notification.Name {
    static let touchBarControlStripPreferenceChanged = Notification.Name(
        "SwiftMumble.touchBarControlStripPreferenceChanged"
    )
}

private extension NSTouchBarItem.Identifier {
    static let swiftMumbleSystemTray = NSTouchBarItem.Identifier(
        "com.leo.SwiftMumble.touchBar.systemTray"
    )
}
