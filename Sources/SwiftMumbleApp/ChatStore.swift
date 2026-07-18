import Foundation
import MumbleProtocol
import Observation

struct ChatEntry: Identifiable, Equatable {
    let id = UUID()
    var author: String
    var timestamp: Date
    var text: String
    var isLocal: Bool
    var isPrivate: Bool = false
    var isMention: Bool = false
}

@MainActor
@Observable
final class ChatStore {
    var draft = ""
    private(set) var entries: [ChatEntry] = []
    var privateMessageTarget: MumbleUser?
    private(set) var logLimit: Int
    private(set) var uses24HourTime: Bool
    /// Messages that arrived while the app was inactive. Drives the Dock badge.
    private(set) var unreadCount = 0
    /// First entry of the current unread run — the "new messages" divider
    /// renders above it so returning users see where they left off.
    private(set) var unreadMarkerID: ChatEntry.ID?

    /// Maintained by the app delegate's active/inactive callbacks; not observed.
    @ObservationIgnored var isApplicationActive = true
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var history: [String] = []
    @ObservationIgnored private var historyIndex: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        logLimit = Self.clampedLogLimit(
            defaults.object(forKey: "chatLogLimit") as? Int ?? 500
        )
        uses24HourTime = defaults.bool(forKey: "chatUses24HourTime")
    }

    func beginConnection(isReconnect: Bool) {
        guard !isReconnect else { return }
        entries.removeAll()
        history.removeAll()
        historyIndex = nil
        clearUnread()
    }

    func clearSession() {
        entries.removeAll()
        draft = ""
        privateMessageTarget = nil
        history.removeAll()
        historyIndex = nil
        clearUnread()
    }

    func acceptOutgoing(_ text: String) {
        draft = ""
        if history.last != text {
            history.append(text)
        }
        historyIndex = nil
        // Sending a message means the user is caught up.
        clearUnread()
    }

    func restoreDraftIfEmpty(_ text: String) {
        if draft.isEmpty {
            draft = text
        }
    }

    func append(_ entry: ChatEntry) {
        if !entry.isLocal, !isApplicationActive {
            if unreadCount == 0 { unreadMarkerID = entry.id }
            unreadCount += 1
        }
        entries.append(entry)
        trimLog()
    }

    /// The app became active: the badge clears, but the divider stays where the
    /// unread run began until the conversation moves on.
    func markRead() {
        unreadCount = 0
    }

    func clearUnread() {
        unreadCount = 0
        unreadMarkerID = nil
    }

    func navigateHistory(older: Bool) {
        guard !history.isEmpty else { return }
        let current = historyIndex ?? history.count
        let next = older ? max(0, current - 1) : min(history.count, current + 1)
        historyIndex = next == history.count ? nil : next
        draft = next == history.count ? "" : history[next]
    }

    func completeUsername(candidates: [String]) {
        let prefix = draft.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        guard !prefix.isEmpty,
              let match = candidates.sorted().first(where: {
                  $0.lowercased().hasPrefix(prefix.lowercased())
              }) else {
            return
        }
        draft.removeLast(prefix.count)
        draft += match + " "
    }

    func appendToDraft(_ text: String) {
        draft += text
    }

    func setLogLimit(_ limit: Int) {
        logLimit = Self.clampedLogLimit(limit)
        defaults.set(logLimit, forKey: "chatLogLimit")
        trimLog()
    }

    func setUses24HourTime(_ enabled: Bool) {
        uses24HourTime = enabled
        defaults.set(enabled, forKey: "chatUses24HourTime")
    }

    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = uses24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    private func trimLog() {
        if entries.count > logLimit {
            entries.removeFirst(entries.count - logLimit)
            if let unreadMarkerID, !entries.contains(where: { $0.id == unreadMarkerID }) {
                self.unreadMarkerID = entries.first?.id
            }
        }
    }

    private static func clampedLogLimit(_ limit: Int) -> Int {
        min(5_000, max(50, limit))
    }
}
