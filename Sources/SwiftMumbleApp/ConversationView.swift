import AppKit
import SwiftUI

struct ConversationView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var session = session

        Group {
            if let channel = session.selectedChannel {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            WelcomeMessage(channelName: channel.name)
                            ForEach(session.chatEntries) { entry in
                                ChatMessage(
                                    author: entry.author,
                                    time: session.formattedChatTime(entry.timestamp),
                                    text: entry.text,
                                    isLocal: entry.isLocal,
                                    isPrivate: entry.isPrivate
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

        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if session.chatDraft.isEmpty && !isComposing {
                    Text(L10n.text("chat.placeholder"))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                NativeTextEditor(
                    text: $session.chatDraft,
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
            .disabled(isEmpty)
            .help(L10n.text("chat.send"))
        }
        .padding(16)
    }

    private var isEmpty: Bool {
        session.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendIfPossible() {
        guard !isEmpty else { return }
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

private struct ChatMessage: View {
    let author: String
    let time: String
    let text: String
    let isLocal: Bool
    var isPrivate: Bool = false

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
    }

    private var accentTint: Color {
        if isPrivate { return .purple }
        return isLocal ? .green : .accentColor
    }
}
