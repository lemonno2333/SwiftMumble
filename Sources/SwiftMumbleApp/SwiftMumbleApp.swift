import SwiftUI

@main
struct SwiftMumbleApp: App {
    @NSApplicationDelegateAdaptor(SwiftMumbleAppDelegate.self) private var appDelegate
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .frame(minWidth: 980, minHeight: 640)
                .onOpenURL { session.openMumbleURL($0) }
                .onAppear { appDelegate.session = session }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.text("server.connectNew")) {
                    session.editingServerID = nil
                    session.isShowingServerSheet = true
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button(L10n.text("channel.returnPrevious")) {
                    session.returnToPreviousChannel()
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!session.canReturnToPreviousChannel)
            }

            CommandMenu(L10n.text("settings.audio")) {
                Button(session.isMuted ? L10n.text("audio.unmute") : L10n.text("audio.mute")) {
                    session.toggleMute()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button(session.isDeafened ? L10n.text("audio.undeafen") : L10n.text("audio.deafen")) {
                    session.toggleDeafen()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(session)
        }

        MenuBarExtra("SwiftMumble", systemImage: session.isMuted ? "mic.slash.fill" : "waveform.circle.fill") {
            Text(session.transportLabel)
            Divider()
            Button(session.isMuted ? L10n.text("audio.unmute") : L10n.text("audio.mute")) { session.toggleMute() }
            Button(session.isDeafened ? L10n.text("audio.undeafen") : L10n.text("audio.deafen")) { session.toggleDeafen() }
            Divider()
            Button(L10n.text("app.show")) { NSApplication.shared.activate(ignoringOtherApps: true) }
            Button(L10n.text("server.disconnect")) { session.disconnect() }
                .disabled(session.connectionState == .disconnected)
            Divider()
            Button(L10n.text("app.quit")) { NSApplication.shared.terminate(nil) }
        }
    }
}
