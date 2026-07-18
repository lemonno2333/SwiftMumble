import Carbon
import Foundation
import KeyboardShortcuts

public enum GlobalPushToTalkHotKeyError: LocalizedError {
    case registrationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            "Could not register the selected global hot key (\(status))."
        }
    }
}

public struct GlobalHotKeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var keyLabel: String

    public init(
        keyCode: UInt32,
        keyLabel: String,
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) {
        self.keyCode = keyCode
        self.keyLabel = keyLabel
        var modifiers: UInt32 = 0
        if command { modifiers |= UInt32(cmdKey) }
        if option { modifiers |= UInt32(optionKey) }
        if control { modifiers |= UInt32(controlKey) }
        if shift { modifiers |= UInt32(shiftKey) }
        carbonModifiers = modifiers
    }

    public static let `default` = GlobalHotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        keyLabel: "Space",
        option: true,
        control: true
    )

    public var displayName: String {
        var value = ""
        if carbonModifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyLabel
    }

    public var keyboardShortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(
            carbonKeyCode: Int(keyCode),
            carbonModifiers: Int(carbonModifiers)
        )
    }

    @MainActor
    public init(keyboardShortcut: KeyboardShortcuts.Shortcut) {
        keyCode = UInt32(keyboardShortcut.carbonKeyCode)
        carbonModifiers = UInt32(keyboardShortcut.carbonModifiers)
        let modifiers = keyboardShortcut.modifiers.ks_symbolicRepresentation
        let description = keyboardShortcut.description
        keyLabel = description.hasPrefix(modifiers)
            ? String(description.dropFirst(modifiers.count))
            : description
    }
}

public struct PushToTalkHotKeyState: Equatable, Sendable {
    public private(set) var isPressed = false

    public init() {}

    public mutating func apply(pressed: Bool) -> Bool? {
        guard pressed != isPressed else { return nil }
        isPressed = pressed
        return pressed
    }
}

@MainActor
public final class GlobalPushToTalkHotKey {
    private static var enabledShortcuts: [UInt32: GlobalHotKeyShortcut] = [:]

    private let name: KeyboardShortcuts.Name
    private let identifierID: UInt32
    private var eventTask: Task<Void, Never>?
    private var state = PushToTalkHotKeyState()
    private var shortcut: GlobalHotKeyShortcut
    private let onPressedChanged: @MainActor @Sendable (Bool) -> Void

    public init(
        shortcut: GlobalHotKeyShortcut = .default,
        identifierID: UInt32 = 1,
        onPressedChanged: @escaping @MainActor @Sendable (Bool) -> Void
    ) throws {
        self.shortcut = shortcut
        self.identifierID = identifierID
        self.onPressedChanged = onPressedChanged
        name = KeyboardShortcuts.Name("SwiftMumble.globalHotKey.\(identifierID)")
        KeyboardShortcuts.setShortcut(shortcut.keyboardShortcut, for: name)
        KeyboardShortcuts.disable(name)
        let events = KeyboardShortcuts.events(for: name)
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                handle(pressed: event == .keyDown)
            }
        }
    }

    deinit {
        eventTask?.cancel()
        let identifierID = identifierID
        Task { @MainActor in
            Self.enabledShortcuts.removeValue(forKey: identifierID)
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if Self.enabledShortcuts[identifierID] == shortcut { return }
            guard !Self.enabledShortcuts.contains(where: { id, registered in
                id != identifierID && registered == shortcut
            }) else {
                throw GlobalPushToTalkHotKeyError.registrationFailed(OSStatus(eventHotKeyExistsErr))
            }
            KeyboardShortcuts.enable(name)
            guard KeyboardShortcuts.isEnabled(for: name) else {
                KeyboardShortcuts.disable(name)
                throw GlobalPushToTalkHotKeyError.registrationFailed(OSStatus(eventHotKeyExistsErr))
            }
            Self.enabledShortcuts[identifierID] = shortcut
        } else {
            KeyboardShortcuts.disable(name)
            Self.enabledShortcuts.removeValue(forKey: identifierID)
            handle(pressed: false)
        }
    }

    public func setShortcut(_ shortcut: GlobalHotKeyShortcut) throws {
        let wasEnabled = Self.enabledShortcuts[identifierID] != nil
        let previousShortcut = self.shortcut
        if wasEnabled { try setEnabled(false) }
        KeyboardShortcuts.setShortcut(shortcut.keyboardShortcut, for: name)
        self.shortcut = shortcut
        guard wasEnabled else { return }
        do {
            try setEnabled(true)
        } catch {
            self.shortcut = previousShortcut
            KeyboardShortcuts.setShortcut(previousShortcut.keyboardShortcut, for: name)
            try? setEnabled(true)
            throw error
        }
    }

    fileprivate func handle(pressed: Bool) {
        guard let changed = state.apply(pressed: pressed) else { return }
        onPressedChanged(changed)
    }
}
