import KeyboardShortcuts
import MumbleSystem
import SwiftUI

struct ShortcutRecorderView: View {
    let shortcut: GlobalHotKeyShortcut
    let onChange: (GlobalHotKeyShortcut) -> Void

    var body: some View {
        KeyboardShortcuts.Recorder(shortcut: Binding(
            get: { shortcut.keyboardShortcut },
            set: { recorded in
                guard let recorded else {
                    onChange(shortcut)
                    return
                }
                onChange(GlobalHotKeyShortcut(keyboardShortcut: recorded))
            }
        ))
        .frame(minWidth: 120)
        .help(L10n.text("settings.globalShortcut"))
    }
}
