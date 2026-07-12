import MumbleProtocol
import SwiftUI

struct ACLManagementView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let channel: MumbleChannel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.text("acl.title", channel.name), systemImage: "lock.shield")
                .font(.title2.weight(.semibold))
            if session.isLoadingACL { ProgressView().frame(maxWidth: .infinity, minHeight: 260) }
            else if let configuration = session.aclConfiguration {
                ACLConfigurationForm(configuration: configuration)
                    .environment(session)
            } else { ContentUnavailableView(L10n.text("acl.unavailable"), systemImage: "lock.slash") }
            HStack { Spacer(); Button(L10n.text("common.close")) { dismiss() } }
        }
        .padding(20).frame(width: 720, height: 620)
        .onAppear { session.requestACL(for: channel) }
    }
}

private struct ACLConfigurationForm: View {
    @Environment(SessionStore.self) private var session
    @State var configuration: MumbleACLConfiguration

    var body: some View {
        Form {
            Toggle(L10n.text("acl.inherit"), isOn: $configuration.inheritACLs)
            Section(L10n.text("acl.groups")) {
                ForEach(Array(configuration.groups.indices), id: \.self) { index in
                    HStack {
                        TextField(L10n.text("acl.groupName"), text: $configuration.groups[index].name)
                            .disabled(configuration.groups[index].inherited)
                        Toggle(L10n.text("acl.group.inheritMembers"), isOn: $configuration.groups[index].inherit)
                        Toggle(L10n.text("acl.group.inheritable"), isOn: $configuration.groups[index].inheritable)
                        if !configuration.groups[index].inherited {
                            Button(role: .destructive) { configuration.groups.remove(at: index) } label: { Image(systemName: "trash") }
                        }
                    }
                }
                Button(L10n.text("acl.group.add"), systemImage: "plus") {
                    configuration.groups.append(MumbleACLGroup(name: uniqueGroupName()))
                }
            }
            Section(L10n.text("acl.entries")) {
                ForEach(Array(configuration.entries.indices), id: \.self) { index in
                    let inherited = configuration.entries[index].inherited
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField(L10n.text("acl.groupName"), text: groupBinding(index))
                                .frame(width: 150)
                            Toggle(L10n.text("acl.here"), isOn: $configuration.entries[index].applyHere)
                            Toggle(L10n.text("acl.subs"), isOn: $configuration.entries[index].applySubs)
                            Spacer()
                            if !inherited {
                                Button(role: .destructive) { configuration.entries.remove(at: index) } label: { Image(systemName: "trash") }
                            }
                        }
                        ForEach(ACLPermission.allCases) { permission in
                            Picker(L10n.text(permission.titleKey), selection: permissionBinding(index, permission)) {
                                Text(L10n.text("acl.permission.inherit")).tag(ACLPermissionState.inherit)
                                Text(L10n.text("acl.permission.allow")).tag(ACLPermissionState.allow)
                                Text(L10n.text("acl.permission.deny")).tag(ACLPermissionState.deny)
                            }.pickerStyle(.segmented)
                        }
                    }.disabled(inherited)
                }
                Button(L10n.text("acl.entry.add"), systemImage: "plus") {
                    configuration.entries.append(MumbleACLEntry())
                }
            }
            Button(L10n.text("acl.save")) { session.saveACL(configuration) }
                .buttonStyle(.borderedProminent)
        }.formStyle(.grouped)
    }

    private func uniqueGroupName() -> String {
        var index = 1
        while configuration.groups.contains(where: { $0.name == "group-\(index)" }) { index += 1 }
        return "group-\(index)"
    }

    private func groupBinding(_ index: Int) -> Binding<String> {
        Binding(get: { configuration.entries[index].group ?? "all" }, set: {
            configuration.entries[index].group = $0; configuration.entries[index].userID = nil
        })
    }

    private func permissionBinding(_ index: Int, _ permission: ACLPermission) -> Binding<ACLPermissionState> {
        Binding(get: {
            let entry = configuration.entries[index]
            if entry.grant & permission.rawValue != 0 { return .allow }
            if entry.deny & permission.rawValue != 0 { return .deny }
            return .inherit
        }, set: { state in
            configuration.entries[index].grant &= ~permission.rawValue
            configuration.entries[index].deny &= ~permission.rawValue
            if state == .allow { configuration.entries[index].grant |= permission.rawValue }
            if state == .deny { configuration.entries[index].deny |= permission.rawValue }
        })
    }
}

private enum ACLPermissionState: Hashable { case inherit, allow, deny }
private enum ACLPermission: UInt32, CaseIterable, Identifiable {
    case traverse = 0x2, enter = 0x4, speak = 0x8, muteDeafen = 0x10, move = 0x20
    case makeChannel = 0x40, linkChannel = 0x80, whisper = 0x100, textMessage = 0x200
    case kick = 0x10000, ban = 0x20000, register = 0x40000
    var id: UInt32 { rawValue }
    var titleKey: String { "acl.permission.\(String(describing: self))" }
}

struct RegisteredUsersView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.text("registeredUsers.title"), systemImage: "person.3")
                .font(.title2.weight(.semibold))
            if session.isLoadingRegisteredUsers { ProgressView().frame(maxWidth: .infinity, minHeight: 280) }
            else {
                List(session.registeredUsers) { user in
                    RegisteredUserRow(user: user).environment(session)
                }
            }
            HStack { Spacer(); Button(L10n.text("common.close")) { dismiss() } }
        }.padding(20).frame(width: 620, height: 500).onAppear { session.requestRegisteredUsers() }
    }
}

private struct RegisteredUserRow: View {
    @Environment(SessionStore.self) private var session
    let user: MumbleRegisteredUser
    @State private var name: String
    init(user: MumbleRegisteredUser) { self.user = user; _name = State(initialValue: user.name) }
    var body: some View {
        HStack {
            TextField(L10n.text("registeredUsers.name"), text: $name)
            Text(user.lastSeen).font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("common.save")) { session.renameRegisteredUser(user, to: name) }
            Button(role: .destructive) { session.removeRegisteredUser(user) } label: { Image(systemName: "trash") }
        }
    }
}
