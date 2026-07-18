import Testing
@testable import MumbleSystem

@Test func hotKeyStateFiltersRepeatedPressAndReleaseEvents() {
    var state = PushToTalkHotKeyState()

    #expect(state.apply(pressed: true) == true)
    #expect(state.apply(pressed: true) == nil)
    #expect(state.apply(pressed: false) == false)
    #expect(state.apply(pressed: false) == nil)
}

@Test @MainActor func globalPushToTalkHotKeyRegistersAndUnregisters() throws {
    let hotKey = try GlobalPushToTalkHotKey { _ in }
    try hotKey.setEnabled(true)
    try hotKey.setEnabled(false)
}

@Test @MainActor func globalHotKeysRejectDuplicateEnabledShortcuts() throws {
    let shortcut = GlobalHotKeyShortcut(
        keyCode: 11,
        keyLabel: "B",
        command: true,
        shift: true
    )
    let first = try GlobalPushToTalkHotKey(shortcut: shortcut, identifierID: 9_001) { _ in }
    let second = try GlobalPushToTalkHotKey(shortcut: shortcut, identifierID: 9_002) { _ in }

    try first.setEnabled(true)
    #expect(throws: GlobalPushToTalkHotKeyError.self) {
        try second.setEnabled(true)
    }
    try first.setEnabled(false)
}

@Test func customHotKeyBuildsNativeDisplayName() {
    let shortcut = GlobalHotKeyShortcut(
        keyCode: 11,
        keyLabel: "B",
        command: true,
        shift: true
    )
    #expect(shortcut.displayName == "⇧⌘B")
}

@Test @MainActor func customHotKeyRoundTripsThroughKeyboardShortcuts() {
    let shortcut = GlobalHotKeyShortcut(
        keyCode: 11,
        keyLabel: "B",
        command: true,
        shift: true
    )

    let restored = GlobalHotKeyShortcut(keyboardShortcut: shortcut.keyboardShortcut)

    #expect(restored.keyCode == shortcut.keyCode)
    #expect(restored.carbonModifiers == shortcut.carbonModifiers)
    #expect(restored.displayName == "⇧⌘B")
}
