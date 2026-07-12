import Foundation

/// Drives one mixer read per 10ms audio frame on a dedicated high-priority
/// queue. Packet arrival order can no longer make concurrent speakers play as
/// separate back-to-back frames.
public final class AudioMixClock: @unchecked Sendable {
    public typealias TickHandler = @Sendable () -> Bool

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.leo.SwiftMumble.audioMixClock", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    public init() {}

    public var isRunning: Bool {
        lock.withLock { timer != nil }
    }

    public func start(handler: @escaping TickHandler) {
        let timer: DispatchSourceTimer? = lock.withLock {
            guard self.timer == nil else { return nil }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            self.timer = timer
            return timer
        }
        guard let timer else { return }
        timer.schedule(
            deadline: .now() + .milliseconds(10),
            repeating: .milliseconds(5),
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in
            if !handler() { self?.stop() }
        }
        timer.resume()
    }

    public func stop() {
        let timer = lock.withLock {
            let timer = self.timer
            self.timer = nil
            return timer
        }
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
