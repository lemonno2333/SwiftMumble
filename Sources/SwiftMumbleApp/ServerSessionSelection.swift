import Foundation

struct ServerSessionSelection<ID: Equatable & Sendable>: Equatable, Sendable {
    private(set) var selectedID: ID?
    private(set) var activeID: ID?

    init(selectedID: ID? = nil, activeID: ID? = nil) {
        self.selectedID = selectedID
        self.activeID = activeID
    }

    @discardableResult
    mutating func select(_ id: ID?) -> Bool {
        guard activeID == nil || activeID == id, selectedID != id else { return false }
        selectedID = id
        return true
    }

    @discardableResult
    mutating func forceSelect(_ id: ID?) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        return true
    }

    @discardableResult
    mutating func beginSession(serverID: ID) -> Bool {
        let selectionChanged = selectedID != serverID
        selectedID = serverID
        activeID = serverID
        return selectionChanged
    }

    mutating func endSession() {
        activeID = nil
    }
}
