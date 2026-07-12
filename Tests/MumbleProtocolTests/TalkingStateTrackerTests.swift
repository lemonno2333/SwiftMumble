import Testing
@testable import MumbleProtocol

@Test func talkingTrackerMarksAndReportsChange() {
    var tracker = TalkingStateTracker(timeout: 0.25)

    #expect(tracker.markActive(session: 3, now: 1) == true)
    #expect(tracker.isTalking(3))
    // A second frame for an already-talking session is not a change.
    #expect(tracker.markActive(session: 3, now: 1.1) == false)
    #expect(tracker.talkingSessions == [3])
}

@Test func talkingTrackerClearsExplicitly() {
    var tracker = TalkingStateTracker()
    tracker.markActive(session: 5, now: 0)

    #expect(tracker.clear(session: 5) == true)
    #expect(!tracker.isTalking(5))
    #expect(tracker.clear(session: 5) == false)
}

@Test func talkingTrackerPrunesAfterTimeout() {
    var tracker = TalkingStateTracker(timeout: 0.25)
    tracker.markActive(session: 1, now: 0)
    tracker.markActive(session: 2, now: 0.2)

    // At now=0.25, session 1 (age 0.25) expires; session 2 (age 0.05) survives.
    #expect(tracker.pruneExpired(now: 0.25) == true)
    #expect(tracker.talkingSessions == [2])
    // Nothing left to prune yet.
    #expect(tracker.pruneExpired(now: 0.3) == false)
    #expect(tracker.pruneExpired(now: 0.45) == true)
    #expect(tracker.talkingSessions.isEmpty)
}
