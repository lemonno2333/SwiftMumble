import MumbleProtocol
import MumbleSystem
import SwiftUI

struct ServerEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let server: MumbleServer?
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var accessTokens: String
    @State private var certificateFingerprint: String
    @State private var savePassword: Bool

    init(server: MumbleServer? = nil) {
        self.server = server
        let storedPassword = server.flatMap {
            try? KeychainPasswordStore.load(account: $0.id.uuidString)
        } ?? nil
        _name = State(initialValue: server?.name ?? "")
        _host = State(initialValue: server?.host ?? "")
        _port = State(initialValue: String(server?.port ?? 64738))
        _username = State(initialValue: server?.username ?? NSFullUserName())
        _password = State(initialValue: storedPassword ?? "")
        let storedTokens = server.flatMap {
            try? KeychainAccessTokenStore.load(account: $0.id.uuidString)
        } ?? []
        _accessTokens = State(initialValue: storedTokens.joined(separator: ", "))
        _certificateFingerprint = State(initialValue: server?.certificateFingerprint ?? "")
        _savePassword = State(initialValue: storedPassword != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(server == nil ? L10n.text("server.editor.addTitle") : L10n.text("server.editor.editTitle"))
                    .font(.title2.weight(.semibold))
            }

            Form {
                TextField(L10n.text("server.name"), text: $name, prompt: Text(L10n.text("server.name.placeholder")))
                TextField(L10n.text("server.address"), text: $host, prompt: Text("voice.example.com"))
                TextField(L10n.text("server.port"), text: $port)
                TextField(L10n.text("server.username"), text: $username)
                SecureField(L10n.text("server.password"), text: $password)
                Toggle(L10n.text("server.password.save"), isOn: $savePassword)
                    .disabled(server == nil && password.isEmpty)
                TextField(L10n.text("server.accessTokens"), text: $accessTokens, axis: .vertical)
                    .lineLimit(1...3)
                Text(L10n.text("server.accessTokens.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup(L10n.text("certificate.title")) {
                    TextField(L10n.text("certificate.fingerprint"), text: $certificateFingerprint)
                    Text(L10n.text("certificate.fingerprint.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), role: .cancel) { dismiss() }
                Button(server == nil ? L10n.text("server.addConnect") : L10n.text("common.save")) {
                    let updatedServer = MumbleServer(
                        id: server?.id ?? UUID(),
                        name: name.isEmpty ? host : name,
                        host: host,
                        port: UInt16(port) ?? 64738,
                        username: username,
                        certificateFingerprint: certificateFingerprint.isEmpty ? nil : certificateFingerprint,
                        isFavorite: server?.isFavorite ?? false
                    )
                    if server == nil {
                        session.addServer(
                            updatedServer,
                            password: password,
                            savePassword: savePassword,
                            accessTokens: parsedAccessTokens
                        )
                    } else {
                        session.updateServer(
                            updatedServer,
                            password: password,
                            savePassword: savePassword,
                            accessTokens: parsedAccessTokens
                        )
                    }
                    dismiss()
                    if server == nil {
                        session.connect(password: password)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var parsedAccessTokens: [String] {
        accessTokens
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
