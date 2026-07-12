import SwiftUI

struct ServerInformationView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(session.selectedServer?.name ?? "Mumble", systemImage: "server.rack")
                .font(.title2.weight(.semibold))
            Form {
                LabeledContent(L10n.text("serverInfo.address"), value: session.selectedServer.map { "\($0.host):\($0.port)" } ?? "-")
                LabeledContent(L10n.text("serverInfo.transport"), value: session.transportLabel)
                LabeledContent(L10n.text("serverInfo.controlPing"), value: session.lastControlPingMilliseconds.map { String(format: "%.1f ms", $0) } ?? "-")
                LabeledContent(L10n.text("serverInfo.users"), value: "\(session.flattenedChannels.flatMap(\.users).count) / \(session.serverMaximumUsers.map(String.init) ?? "-")")
                LabeledContent(L10n.text("serverInfo.bandwidth"), value: session.serverMaximumBandwidth.map { "\($0 / 1000) kbit/s" } ?? "-")
                LabeledContent(L10n.text("serverInfo.messageLimit"), value: "\(session.serverMessageLengthLimit)")
                LabeledContent(L10n.text("serverInfo.imageLimit"), value: "\(session.serverImageMessageLengthLimit)")
                LabeledContent(L10n.text("serverInfo.recording"), value: session.serverRecordingAllowed ? L10n.text("common.yes") : L10n.text("common.no"))
                LabeledContent(L10n.text("serverInfo.proxy"), value: session.proxyType == .none ? L10n.text("settings.proxy.none") : session.proxyType.rawValue)
                if let fingerprint = session.selectedServer?.certificateFingerprint {
                    LabeledContent("SHA-256", value: fingerprint).textSelection(.enabled)
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button(L10n.text("common.close")) { dismiss() } }
        }.padding(20).frame(width: 560, height: 520)
    }
}
