import Carbon
import Foundation

public enum GlobalPushToTalkHotKeyError: LocalizedError {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .eventHandlerInstallationFailed(let status):
            "Could not install the global hot key event handler (\(status))."
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

public final class GlobalPushToTalkHotKey: @unchecked Sendable {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var state = PushToTalkHotKeyState()
    private var shortcut: GlobalHotKeyShortcut
    private let onPressedChanged: @MainActor @Sendable (Bool) -> Void
    private let identifierID: UInt32

    public init(
        shortcut: GlobalHotKeyShortcut = .default,
        identifierID: UInt32 = 1,
        onPressedChanged: @escaping @MainActor @Sendable (Bool) -> Void
    ) throws {
        self.shortcut = shortcut
        self.identifierID = identifierID
        self.onPressedChanged = onPressedChanged
        let eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        let status = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                globalPushToTalkEventHandler,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
        }
        guard status == noErr else {
            throw GlobalPushToTalkHotKeyError.eventHandlerInstallationFailed(status)
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard hotKey == nil else { return }
            let identifier = EventHotKeyID(signature: fourCharacterCode("NMHK"), id: identifierID)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.carbonModifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &hotKey
            )
            guard status == noErr else {
                hotKey = nil
                throw GlobalPushToTalkHotKeyError.registrationFailed(status)
            }
        } else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            handle(pressed: false)
        }
    }

    public func setShortcut(_ shortcut: GlobalHotKeyShortcut) throws {
        let wasEnabled = hotKey != nil
        if wasEnabled { try setEnabled(false) }
        self.shortcut = shortcut
        if wasEnabled { try setEnabled(true) }
    }

    fileprivate func handle(pressed: Bool) {
        guard let changed = state.apply(pressed: pressed) else { return }
        Task { @MainActor in onPressedChanged(changed) }
    }
}

private let globalPushToTalkEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<GlobalPushToTalkHotKey>.fromOpaque(userData).takeUnretainedValue()
    switch GetEventKind(event) {
    case UInt32(kEventHotKeyPressed):
        monitor.handle(pressed: true)
    case UInt32(kEventHotKeyReleased):
        monitor.handle(pressed: false)
    default:
        return OSStatus(eventNotHandledErr)
    }
    return noErr
}

private func fourCharacterCode(_ value: String) -> FourCharCode {
    value.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
}
