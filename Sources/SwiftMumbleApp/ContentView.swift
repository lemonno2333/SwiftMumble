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
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if session.isReconnecting {
                    ReconnectingBanner()
                        .environment(session)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let audioError = session.audioErrorMessage {
                    AudioErrorBanner(message: audioError) {
                        session.audioErrorMessage = nil
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy, value: session.isReconnecting)
        .animation(.snappy, value: session.audioErrorMessage)
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

private struct AudioErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.badge.exclamationmark")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("audio.banner.title"))
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(L10n.text("common.close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.red.opacity(0.1))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReconnectingBanner: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(.orange)

            Image(systemName: "network.slash")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.connectionLabel)
                    .font(.headline)
                if let server = session.activeServer ?? session.selectedServer {
                    Text("\(server.name)  \(server.host):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Button(L10n.text("server.disconnect"), role: .cancel) {
                session.disconnect()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
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

            Text(L10n.text(
                certificate.previousFingerprint == nil
                    ? "certificate.verify.message"
                    : "certificate.mismatch.message",
                certificate.host
            ))
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
                if let previousFingerprint = certificate.previousFingerprint {
                    GridRow(alignment: .top) {
                        Text(L10n.text("certificate.previousFingerprint"))
                            .foregroundStyle(.secondary)
                        Text(previousFingerprint.formatted)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
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
        Button(action: {}) {
            Label(
                L10n.text("audio.pushToTalk"),
                systemImage: session.isTransmitting ? "waveform" : "mic.badge.plus"
            )
            .symbolEffect(.variableColor.iterative, isActive: session.isTransmitting)
            .foregroundStyle(session.isTransmitting ? Color.green : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .nativeGlass(in: Capsule())
        }
            .buttonStyle(PressAndHoldButtonStyle(
                onPressed: session.beginTransmission,
                onReleased: session.releasePushToTalk
            ))
            .disabled(!isEnabled)
            .help(session.audioErrorMessage ?? L10n.text("audio.pushToTalk.help"))
            .accessibilityAction {
                session.toggleLatchedPushToTalk()
            }
    }

    private var isEnabled: Bool {
        guard !session.isReconnecting else { return false }
        if case .connected = session.connectionState {
            return !session.isMuted && session.transmissionMode == .pushToTalk
        }
        return false
    }
}

private struct PressAndHoldButtonStyle: ButtonStyle {
    var onPressed: () -> Void
    var onReleased: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        PressAndHoldButtonBody(
            label: AnyView(configuration.label),
            isPressed: configuration.isPressed,
            onPressed: onPressed,
            onReleased: onReleased
        )
    }

    private struct PressAndHoldButtonBody: View {
        let label: AnyView
        let isPressed: Bool
        let onPressed: () -> Void
        let onReleased: () -> Void
        @State private var isHandlingPress = false

        var body: some View {
            label
                .opacity(isPressed ? 0.78 : 1)
                .onChange(of: isPressed) { _, newValue in
                    guard newValue != isHandlingPress else { return }
                    isHandlingPress = newValue
                    if newValue { onPressed() }
                    else { onReleased() }
                }
                .onDisappear {
                    guard isHandlingPress else { return }
                    isHandlingPress = false
                    onReleased()
                }
        }
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
