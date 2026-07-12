import AppKit
import MumbleSystem
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalHotKeyShortcut
    let onRecordingChanged: (Bool) -> Void
    let onChange: (GlobalHotKeyShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onRecordingChanged = onRecordingChanged
        button.onChange = onChange
        button.refreshTitle()
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var shortcut = GlobalHotKeyShortcut.default
    var onRecordingChanged: ((Bool) -> Void)?
    var onChange: ((GlobalHotKeyShortcut) -> Void)?
    private(set) var isRecordingShortcut = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(toggleRecording)
        setButtonType(.momentaryPushIn)
        toolTip = L10n.text("settings.globalShortcut")
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    @objc private func toggleRecording() {
        if isRecordingShortcut {
            stopRecording()
        } else {
            isRecordingShortcut = true
            onRecordingChanged?(true)
            refreshTitle()
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control, .shift]).isEmpty else {
            NSSound.beep()
            return
        }
        onChange?(GlobalHotKeyShortcut(
            keyCode: UInt32(event.keyCode),
            keyLabel: Self.keyLabel(for: event),
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        ))
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { stopRecording() }
        return result
    }

    func refreshTitle() {
        title = isRecordingShortcut ? L10n.text("settings.shortcut.pressKeys") : shortcut.displayName
        setAccessibilityLabel(title)
    }

    private func stopRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        onRecordingChanged?(false)
        refreshTitle()
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: "Return"
        case 48: "Tab"
        case 49: "Space"
        case 51: "Delete"
        case 53: "Escape"
        case 115: "Home"
        case 116: "Page Up"
        case 117: "Forward Delete"
        case 119: "End"
        case 121: "Page Down"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
    }
}
