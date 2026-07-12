import MumbleProtocol
import SwiftUI

struct ChannelEditorRequest: Identifiable {
    let id = UUID()
    var channel: MumbleChannel?
    var parentID: UInt32
}

struct ChannelEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let request: ChannelEditorRequest
    @State private var name: String
    @State private var descriptionText: String
    @State private var temporary: Bool
    @State private var position: Int
    @State private var maximumUsers: Int

    init(request: ChannelEditorRequest) {
        self.request = request
        _name = State(initialValue: request.channel?.name ?? "")
        _descriptionText = State(initialValue: request.channel?.descriptionText ?? "")
        _temporary = State(initialValue: request.channel?.isTemporary ?? false)
        _position = State(initialValue: Int(request.channel?.position ?? 0))
        _maximumUsers = State(initialValue: Int(request.channel?.maximumUsers ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                request.channel == nil ? L10n.text("channel.create") : L10n.text("channel.edit"),
                systemImage: request.channel == nil ? "plus.square.on.square" : "pencil"
            )
            .font(.title2.weight(.semibold))

            Form {
                TextField(L10n.text("channel.name"), text: $name)
                TextField(L10n.text("channel.description"), text: $descriptionText, axis: .vertical)
                    .lineLimit(3...8)
                Stepper(L10n.text("channel.position.value", position), value: $position, in: -1000 ... 1000)
                Stepper(L10n.text("channel.maximumUsers.value", maximumUsers), value: $maximumUsers, in: 0 ... 1000)
                if request.channel == nil {
                    Toggle(L10n.text("channel.temporary"), isOn: $temporary)
                }
                Text(L10n.text("channel.maximumUsers.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), role: .cancel) { dismiss() }
                Button(L10n.text("common.save")) {
                    session.saveChannel(
                        request,
                        name: name,
                        description: descriptionText,
                        temporary: temporary,
                        position: Int32(position),
                        maximumUsers: maximumUsers == 0 ? nil : UInt32(maximumUsers)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
