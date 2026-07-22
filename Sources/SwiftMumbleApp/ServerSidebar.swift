import MumbleProtocol
import SwiftUI

struct ServerSidebar: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var session = session

        List(selection: selectedServerBinding) {
            Section(L10n.text("servers.title")) {
                ForEach(session.servers) { server in
                    ServerRow(server: server)
                        .tag(server.id)
                        .onTapGesture(count: 2) {
                            session.handleServerDoubleClick(server)
                        }
                        .contextMenu {
                            if session.hasActiveSession(for: server) {
                                Button(L10n.text("server.disconnect"), systemImage: "bolt.slash") {
                                    session.disconnect()
                                }
                            } else {
                                Button(L10n.text("server.connect"), systemImage: "bolt") {
                                    session.connect(to: server)
                                }
                            }

                            Divider()

                            Button(L10n.text("server.copyURL"), systemImage: "link") {
                                session.copyURL(session.serverURL(for: server))
                            }
                            if session.canUseServerSessionActions(for: server), session.hasPermission(.register) {
                                Button(L10n.text("registeredUsers.title"), systemImage: "person.3") {
                                    session.isShowingRegisteredUsers = true
                                }
                            }
                            Button(L10n.text("serverInfo.title"), systemImage: "info.circle") {
                                session.isShowingServerInformation = true
                            }
                            .disabled(!session.canUseServerSessionActions(for: server))
                            if session.canUseServerSessionActions(for: server) {
                                ForEach(session.contextActions(for: 1)) { action in
                                    Button(action.title, systemImage: "command") { session.performContextAction(action) }
                                }
                            }

                            Button(L10n.text("common.edit"), systemImage: "pencil") {
                                session.editingServerID = server.id
                                session.isShowingServerSheet = true
                            }

                            Divider()

                            Button(L10n.text("common.delete"), systemImage: "trash", role: .destructive) {
                                session.pendingServerDeletion = server
                            }
                        }
                }
            }

            if !session.discoveredServers.isEmpty {
                Section(L10n.text("servers.localNetwork")) {
                    ForEach(session.discoveredServers) { server in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                Text("\(server.host):\(server.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "bonjour") }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            session.connectToDiscoveredServer(server)
                        }
                        .selectionDisabled(true)
                        .contextMenu {
                            Button(L10n.text("server.addAndConnect"), systemImage: "bolt.badge.plus") {
                                session.connectToDiscoveredServer(server)
                            }
                        }
                    }
                }
            }

            if session.publicServerDirectoryEnabled {
                Section(L10n.text("servers.public")) {
                    if session.isLoadingPublicServers {
                        ProgressView()
                            .controlSize(.small)
                            .selectionDisabled(true)
                    }
                    ForEach(session.publicServers.prefix(200)) { server in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name).lineLimit(1)
                                Text([server.countryCode.uppercased(), "\(server.host):\(server.port)"].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let ping = session.publicServerPingResults[server.id] {
                                    Text(L10n.text("servers.public.ping", Int(ping.latencyMilliseconds.rounded()), ping.users, ping.maximumUsers))
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        } icon: { Image(systemName: "globe") }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            session.connectToPublicServer(server)
                        }
                        .selectionDisabled(true)
                    }
                    if let error = session.publicServerError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .selectionDisabled(true)
                    }
                    Button(L10n.text("servers.public.refresh"), systemImage: "arrow.clockwise") {
                        session.refreshPublicServers()
                    }
                    .selectionDisabled(true)
                    Button(L10n.text("servers.public.measure"), systemImage: "gauge.with.dots.needle.33percent") {
                        session.pingVisiblePublicServers()
                    }
                    .disabled(session.isPingingPublicServers)
                    .selectionDisabled(true)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    session.editingServerID = nil
                    session.isShowingServerSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(L10n.text("server.add"))

                Spacer()

                Text(session.transportLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .navigationTitle("Mumble")
    }

    private var selectedServerBinding: Binding<MumbleServer.ID?> {
        Binding(
            get: { session.selectedServerID },
            set: { id in
                guard let id, let server = session.servers.first(where: { $0.id == id }) else { return }
                session.selectServer(server)
            }
        )
    }
}

private struct ServerRow: View {
    let server: MumbleServer

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                Text(server.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: server.isFavorite ? "server.rack" : "network")
                .symbolRenderingMode(.hierarchical)
        }
        .padding(.vertical, 3)
    }
}
