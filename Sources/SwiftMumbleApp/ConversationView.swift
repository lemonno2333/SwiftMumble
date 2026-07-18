import AppKit
import SwiftUI

struct ConversationView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var session = session
        @Bindable var chat = session.chat

        Group {
            if let channel = session.selectedChannel {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            WelcomeMessage(channelName: channel.name)
                            ForEach(chat.entries) { entry in
                                if entry.id == chat.unreadMarkerID {
                                    UnreadDivider()
                                }
                                ChatMessage(
                                    author: entry.author,
                                    time: session.formattedChatTime(entry.timestamp),
                                    text: entry.text,
                                    isLocal: entry.isLocal,
                                    isPrivate: entry.isPrivate,
                                    isMention: entry.isMention
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                    }

                    Divider()

                    ChatComposer().environment(session)
                }
            } else {
                ContentUnavailableView(
                    L10n.text("channel.noneSelected"),
                    systemImage: "bubble.left.and.waveform.right",
                    description: Text(L10n.text("channel.noneSelected.help"))
                )
            }
        }
        .navigationTitle(session.selectedChannel?.name ?? L10n.text("chat.title"))
        .navigationSubtitle(peopleLabel)
    }

    private var peopleLabel: String {
        let count = session.selectedChannel?.users.count ?? 0
        return count == 1 ? L10n.text("people.one") : L10n.text("people.many", count)
    }
}

private struct ChatComposer: View {
    @Environment(SessionStore.self) private var session
    @State private var editorHeight: CGFloat = 24
    @State private var isComposing = false

    var body: some View {
        @Bindable var session = session
        @Bindable var chat = session.chat

        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if chat.draft.isEmpty && !isComposing {
                    Text(L10n.text("chat.placeholder"))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                NativeTextEditor(
                    text: $chat.draft,
                    contentHeight: $editorHeight,
                    onSubmit: sendIfPossible,
                    onComplete: session.completeChatUsername,
                    onHistoryUp: { session.navigateChatHistory(older: true) },
                    onHistoryDown: { session.navigateChatHistory(older: false) },
                    onCompositionChange: { isComposing = $0 }
                )
            }
                .frame(height: editorHeight)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .nativeGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button { session.pasteImageIntoChat() } label: {
                Image(systemName: "photo.on.rectangle")
            }
            .help(L10n.text("chat.pasteImage"))

            Button(action: sendIfPossible) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(isEmpty || !isConnected)
            .help(L10n.text("chat.send"))
        }
        .padding(16)
    }

    private var isEmpty: Bool {
        session.chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isConnected: Bool {
        if case .connected = session.connectionState { return true }
        return false
    }

    private func sendIfPossible() {
        guard !isEmpty, isConnected else { return }
        session.sendChatMessage()
    }
}

private struct WelcomeMessage: View {
    let channelName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text(L10n.text("channel.welcome", channelName))
                .font(.title2.weight(.semibold))
            Text(L10n.text("channel.welcome.help"))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

private struct UnreadDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.red.opacity(0.45)).frame(height: 1)
            Text(L10n.text("chat.unreadDivider"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .fixedSize()
            Rectangle().fill(.red.opacity(0.45)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChatMessage: View {
    let author: String
    let time: String
    let text: String
    let isLocal: Bool
    var isPrivate: Bool = false
    var isMention: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(accentTint.opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay {
                    if isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(accentTint)
                    } else {
                        Text(author.prefix(1))
                            .font(.callout.weight(.semibold))
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(author)
                        .fontWeight(.semibold)
                        .foregroundStyle(isPrivate ? accentTint : .primary)
                    if isMention {
                        Image(systemName: "at")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                            .help(L10n.text("chat.mentionsYou"))
                    }
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                RichMessageView(html: text)
                    .frame(minHeight: 20)
                    .contextMenu {
                        if !MessageText.embeddedImages(from: text).isEmpty {
                            Button(L10n.text("chat.saveImage"), systemImage: "square.and.arrow.down") {
                                MessageText.saveFirstEmbeddedImage(from: text)
                            }
                        }
                    }
            }
        }
        .padding(isMention ? 8 : 0)
        .background {
            if isMention {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.orange.opacity(0.12))
            }
        }
    }

    private var accentTint: Color {
        if isPrivate { return .purple }
        return isLocal ? .green : .accentColor
    }
}
