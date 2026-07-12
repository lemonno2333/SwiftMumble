import Foundation

public struct PushToTalkHoldConfiguration: Equatable, Sendable {
    public let milliseconds: Int

    public init(milliseconds: Int) {
        self.milliseconds = min(1_000, max(0, milliseconds))
    }

    public var duration: Duration { .milliseconds(milliseconds) }
}
