import MumbleProtocol
import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var session = session

        NavigationSplitView {
            ServerSidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
        } content: {
            ChannelBrowser()
                .navigationSplitViewColumnWidth(min: 330, ideal: 410)
        } detail: {
            ConversationView()
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowBackdrop())
        .toolbar {
            if session.showsReturnToPreviousChannelControl {
                ToolbarItem(placement: .navigation) {
                    Button {
                        session.returnToPreviousChannel()
                    } label: {
                        Label(L10n.text("channel.returnPrevious"), systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!session.canReturnToPreviousChannel)
                    .help(L10n.text("channel.returnPrevious.help"))
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                PushToTalkButton()
                    .environment(session)

                audioButton(
                    title: session.isMuted ? L10n.text("audio.unmute") : L10n.text("audio.mute"),
                    symbol: session.isMuted ? "mic.slash.fill" : "mic.fill",
                    active: session.isMuted
                ) {
                    session.toggleMute()
                }

                audioButton(
                    title: session.isDeafened ? L10n.text("audio.undeafen") : L10n.text("audio.deafen"),
                    symbol: session.isDeafened ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    active: session.isDeafened
                ) {
                    session.toggleDeafen()
                }
            }
        }
        .sheet(isPresented: $session.isShowingServerSheet) {
            ServerEditorView(server: session.editingServer)
                .environment(session)
        }
        .confirmationDialog(
            L10n.text("server.delete.title"),
            isPresented: Binding(
                get: { session.pendingServerDeletion != nil },
                set: { if !$0 { session.pendingServerDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: session.pendingServerDeletion
        ) { server in
            Button(L10n.text("server.delete.action", server.name), role: .destructive) {
                session.deleteServer(server)
            }
        } message: { server in
            Text(L10n.text("server.delete.message", server.name))
        }
        .alert(
            L10n.text("server.error.title"),
            isPresented: Binding(
                get: { session.serverManagementError != nil },
                set: { if !$0 { session.serverManagementError = nil } }
            )
        ) {
            Button(L10n.text("common.ok")) { session.serverManagementError = nil }
        } message: {
            Text(session.serverManagementError ?? L10n.text("error.unknown"))
        }
        .sheet(item: $session.pendingServerCertificate) { certificate in
            CertificateTrustView(certificate: certificate)
                .environment(session)
        }
        .sheet(isPresented: $session.isShowingRegisteredUsers) {
            RegisteredUsersView().environment(session)
        }
        .sheet(isPresented: Binding(get: { session.isShowingServerInformation }, set: { session.isShowingServerInformation = $0 })) {
            ServerInformationView().environment(session)
        }
    }

    private func audioButton(
        title: String,
        symbol: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .symbolRenderingMode(.hierarchical)
        }
        .tint(active ? .red : nil)
        .help(title)
    }
}

private struct CertificateTrustView: View {
    @Environment(SessionStore.self) private var session
    let certificate: PendingServerCertificate

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("certificate.verify.title"), systemImage: "checkmark.shield")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)

            Text(L10n.text("certificate.verify.message", certificate.host))
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.text("certificate.subject"))
                        .foregroundStyle(.secondary)
                    Text(certificate.subject)
                }
                GridRow(alignment: .top) {
                    Text("SHA-256")
                        .foregroundStyle(.secondary)
                    Text(certificate.fingerprint.formatted)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .padding(14)
            .nativeGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), role: .cancel) {
                    session.cancelPendingServerCertificate()
                }
                Button(L10n.text("certificate.trustReconnect")) {
                    session.trustPendingServerCertificate()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct PushToTalkButton: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Label(L10n.text("audio.pushToTalk"), systemImage: session.isTransmitting ? "waveform" : "mic.badge.plus")
            .symbolEffect(.variableColor.iterative, isActive: session.isTransmitting)
            .foregroundStyle(session.isTransmitting ? Color.green : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .nativeGlass(in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .overlay {
                PressAndHoldEventView(
                    isEnabled: isEnabled,
                    onPressed: session.beginTransmission,
                    onReleased: session.releasePushToTalk
                )
            }
            .help(session.audioErrorMessage ?? L10n.text("audio.pushToTalk.help"))
            .accessibilityAddTraits(.isButton)
    }

    private var isEnabled: Bool {
        if case .connected = session.connectionState {
            return !session.isMuted && session.transmissionMode == .pushToTalk
        }
        return false
    }
}

private struct PressAndHoldEventView: NSViewRepresentable {
    var isEnabled: Bool
    var onPressed: () -> Void
    var onReleased: () -> Void

    func makeNSView(context: Context) -> PressAndHoldNSView {
        PressAndHoldNSView()
    }

    func updateNSView(_ view: PressAndHoldNSView, context: Context) {
        view.isEnabled = isEnabled
        view.onPressed = onPressed
        view.onReleased = onReleased
    }
}

private final class PressAndHoldNSView: NSView {
    var isEnabled = true
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let recognizer = NSPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        recognizer.minimumPressDuration = 0
        addGestureRecognizer(recognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handlePress(_ recognizer: NSPressGestureRecognizer) {
        guard isEnabled else {
            releaseIfNeeded()
            return
        }
        switch recognizer.state {
        case .began:
            guard !isPressed else { return }
            isPressed = true
            onPressed?()
        case .ended, .cancelled, .failed:
            releaseIfNeeded()
        default:
            break
        }
    }

    private func releaseIfNeeded() {
        guard isPressed else { return }
        isPressed = false
        onReleased?()
    }
}

private struct WindowBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
