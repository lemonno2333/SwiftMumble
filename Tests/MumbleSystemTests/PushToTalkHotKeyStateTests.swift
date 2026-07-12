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

@Test func customHotKeyBuildsNativeDisplayName() {
    let shortcut = GlobalHotKeyShortcut(
        keyCode: 11,
        keyLabel: "B",
        command: true,
        shift: true
    )
    #expect(shortcut.displayName == "⇧⌘B")
}
