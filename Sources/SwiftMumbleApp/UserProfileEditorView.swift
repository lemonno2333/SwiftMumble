import AppKit
import MumbleProtocol
import SwiftUI
import UniformTypeIdentifiers

struct UserProfileEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let user: MumbleUser
    @State private var nickname: String
    @State private var comment: String
    @State private var avatarData: Data?

    init(user: MumbleUser, nickname: String) {
        self.user = user
        _nickname = State(initialValue: nickname)
        _comment = State(initialValue: user.commentText)
        _avatarData = State(initialValue: user.avatarData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(session.displayName(for: user), systemImage: "person.crop.circle")
                .font(.title2.weight(.semibold))
            Form {
                TextField(L10n.text("user.localNickname"), text: $nickname)
                if isOwnUser {
                    TextEditor(text: $comment)
                        .frame(minHeight: 100)
                    HStack {
                        avatar
                        Button(L10n.text("user.avatar.choose")) { chooseAvatar() }
                        Button(L10n.text("user.avatar.remove"), role: .destructive) { avatarData = Data() }
                    }
                }
            }
            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), role: .cancel) { dismiss() }
                Button(L10n.text("common.save")) {
                    session.setLocalNickname(nickname, for: user)
                    if isOwnUser { session.updateOwnProfile(comment: comment, avatarData: avatarData) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private var isOwnUser: Bool {
        if case .connected(let sessionID) = session.connectionState { return sessionID == user.id }
        return false
    }

    @ViewBuilder private var avatar: some View {
        if let data = avatarData, !data.isEmpty, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(.circle)
        } else {
            Image(systemName: "person.crop.circle").font(.system(size: 46)).foregroundStyle(.secondary)
        }
    }

    private func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return }
        avatarData = data
    }
}
