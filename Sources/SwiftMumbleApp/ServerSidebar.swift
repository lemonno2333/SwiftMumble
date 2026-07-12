import MumbleProtocol
import SwiftUI

struct ServerSidebar: View {
    @Environment(SessionStore.self) private var session
    @State private var highlightedServerID: MumbleServer.ID?

    var body: some View {
        @Bindable var session = session

        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    serverSectionHeader(L10n.text("servers.title"))
                ForEach(session.servers) { server in
                    Button {
                        highlightedServerID = server.id
                        session.selectedServerID = server.id
                    } label: {
                        ServerRow(server: server)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(highlightedServerID == server.id ? Color.accentColor.opacity(0.22) : .clear)
                            }
                    }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            session.handleServerDoubleClick(server)
                        })
                        .contextMenu {
                            if session.selectedServerID == server.id,
                               session.connectionState != .disconnected {
                                Button(L10n.text("server.disconnect"), systemImage: "bolt.slash") {
                                    session.disconnect()
                                }
                            } else {
                                Button(L10n.text("server.connect"), systemImage: "bolt") {
                                    session.selectedServerID = server.id
                                    session.connect()
                                }
                            }

                            Divider()

                            Button(L10n.text("server.copyURL"), systemImage: "link") {
                                session.selectedServerID = server.id
                                session.copyURL(session.serverURL())
                            }
                            Button(L10n.text("registeredUsers.title"), systemImage: "person.3") {
                                session.selectedServerID = server.id
                                session.isShowingRegisteredUsers = true
                            }
                            Button(L10n.text("serverInfo.title"), systemImage: "info.circle") {
                                session.selectedServerID = server.id; session.isShowingServerInformation = true
                            }
                            ForEach(session.contextActions(for: 1)) { action in
                                Button(action.title, systemImage: "command") { session.performContextAction(action) }
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
            if !session.discoveredServers.isEmpty {
                serverSectionHeader(L10n.text("servers.localNetwork"))
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
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            session.connectToDiscoveredServer(server)
                        })
                        .contextMenu {
                            Button(L10n.text("server.addAndConnect"), systemImage: "bolt.badge.plus") {
                                session.connectToDiscoveredServer(server)
                            }
                        }
                    }
            }
            if session.publicServerDirectoryEnabled {
                serverSectionHeader(L10n.text("servers.public"))
                    if session.isLoadingPublicServers { ProgressView().controlSize(.small) }
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
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            session.connectToPublicServer(server)
                        })
                    }
                    if let error = session.publicServerError { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(L10n.text("servers.public.refresh"), systemImage: "arrow.clockwise") { session.refreshPublicServers() }
                    Button(L10n.text("servers.public.measure"), systemImage: "gauge.with.dots.needle.33percent") {
                        session.pingVisiblePublicServers()
                    }.disabled(session.isPingingPublicServers)
            }
                    Spacer(minLength: 40)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { highlightedServerID = nil }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
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

    private func serverSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
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
