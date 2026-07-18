import Foundation
import Testing
@testable import SwiftMumbleApp

@MainActor
@Test func chatStoreNavigatesAcceptedOutgoingHistory() {
    let store = ChatStore(defaults: isolatedDefaults())
    store.acceptOutgoing("first")
    store.acceptOutgoing("second")

    store.navigateHistory(older: true)
    #expect(store.draft == "second")
    store.navigateHistory(older: true)
    #expect(store.draft == "first")
    store.navigateHistory(older: false)
    #expect(store.draft == "second")
    store.navigateHistory(older: false)
    #expect(store.draft.isEmpty)
}

@MainActor
@Test func chatStoreTrimsEntriesWhenLimitChanges() {
    let store = ChatStore(defaults: isolatedDefaults())
    for index in 0 ..< 55 {
        store.append(
            ChatEntry(
                author: "User",
                timestamp: Date(timeIntervalSince1970: Double(index)),
                text: "message-\(index)",
                isLocal: false
            )
        )
    }

    store.setLogLimit(50)

    #expect(store.entries.count == 50)
    #expect(store.entries.first?.text == "message-5")
    #expect(store.entries.last?.text == "message-54")
}

@MainActor
@Test func chatStoreRestoresFailedDraftWithoutOverwritingNewInput() {
    let store = ChatStore(defaults: isolatedDefaults())
    store.acceptOutgoing("original")
    store.restoreDraftIfEmpty("original")
    #expect(store.draft == "original")

    store.draft = "new input"
    store.restoreDraftIfEmpty("original")
    #expect(store.draft == "new input")
}

@MainActor
@Test func chatStoreClearsHistoryForNewConnectionButKeepsItForReconnect() {
    let store = ChatStore(defaults: isolatedDefaults())
    store.acceptOutgoing("before reconnect")
    store.beginConnection(isReconnect: true)
    store.navigateHistory(older: true)
    #expect(store.draft == "before reconnect")

    store.beginConnection(isReconnect: false)
    store.draft = ""
    store.navigateHistory(older: true)
    #expect(store.draft.isEmpty)
}

@MainActor
@Test func chatStoreTracksUnreadWhileInactiveAndClearsOnRead() {
    let store = ChatStore(defaults: isolatedDefaults())
    store.isApplicationActive = false

    let first = ChatEntry(author: "A", timestamp: Date(), text: "hi", isLocal: false)
    store.append(first)
    store.append(ChatEntry(author: "B", timestamp: Date(), text: "there", isLocal: false))
    #expect(store.unreadCount == 2)
    // Divider anchors to the first message of the unread run.
    #expect(store.unreadMarkerID == first.id)

    // Becoming active clears the badge but keeps the divider in place.
    store.markRead()
    #expect(store.unreadCount == 0)
    #expect(store.unreadMarkerID == first.id)
}

@MainActor
@Test func chatStoreDoesNotCountOwnMessagesOrActiveMessagesAsUnread() {
    let store = ChatStore(defaults: isolatedDefaults())
    // Active app: incoming message is seen immediately.
    store.isApplicationActive = true
    store.append(ChatEntry(author: "A", timestamp: Date(), text: "seen", isLocal: false))
    #expect(store.unreadCount == 0)

    // Inactive, but our own echoed message never counts as unread.
    store.isApplicationActive = false
    store.append(ChatEntry(author: "Me", timestamp: Date(), text: "mine", isLocal: true))
    #expect(store.unreadCount == 0)
    #expect(store.unreadMarkerID == nil)
}

@MainActor
@Test func chatStoreSendingClearsUnread() {
    let store = ChatStore(defaults: isolatedDefaults())
    store.isApplicationActive = false
    store.append(ChatEntry(author: "A", timestamp: Date(), text: "ping", isLocal: false))
    #expect(store.unreadCount == 1)

    store.acceptOutgoing("reply")
    #expect(store.unreadCount == 0)
    #expect(store.unreadMarkerID == nil)
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "ChatStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
