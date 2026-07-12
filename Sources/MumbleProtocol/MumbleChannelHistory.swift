public struct MumbleChannelHistory: Equatable, Sendable {
    public private(set) var currentChannelID: UInt32?
    public private(set) var previousChannelID: UInt32?

    public init() {}

    @discardableResult
    public mutating func observe(channelID: UInt32) -> Bool {
        guard channelID != currentChannelID else { return false }
        previousChannelID = currentChannelID
        currentChannelID = channelID
        return true
    }

    public mutating func reset() {
        currentChannelID = nil
        previousChannelID = nil
    }
}
