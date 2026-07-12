import MumbleProtocol
import SwiftUI

enum UserModerationAction: String, Identifiable {
    case kick, ban
    var id: String { rawValue }
}

struct UserModerationRequest: Identifiable {
    let id = UUID()
    var user: MumbleUser
    var action: UserModerationAction
}

struct UserModerationView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let request: UserModerationRequest
    @State private var reason = ""
    @State private var banCertificate = true
    @State private var banIP = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                L10n.text(request.action == .ban ? "moderation.ban.title" : "moderation.kick.title", request.user.name),
                systemImage: request.action == .ban ? "hand.raised.fill" : "person.crop.circle.badge.xmark"
            )
            .font(.title2.weight(.semibold))
            TextField(L10n.text("moderation.reason"), text: $reason, axis: .vertical)
                .lineLimit(2 ... 5)
            if request.action == .ban {
                Toggle(L10n.text("moderation.banCertificate"), isOn: $banCertificate)
                Toggle(L10n.text("moderation.banIP"), isOn: $banIP)
            }
            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), role: .cancel) { dismiss() }
                Button(L10n.text(request.action == .ban ? "moderation.ban.action" : "moderation.kick.action"), role: .destructive) {
                    session.performModeration(
                        request,
                        reason: reason,
                        banCertificate: banCertificate,
                        banIP: banIP
                    )
                    dismiss()
                }
            }
        }
        .padding(22)
        .frame(width: 450)
    }
}
