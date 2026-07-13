import Foundation
import Testing
@testable import MumbleAudio

@Test func adaptiveEchoCancellerReducesCorrelatedPlaybackEcho() {
    let canceller = AdaptiveEchoCanceller()
    let reference = (0..<480).map { Float(sin(Double($0) * 0.08)) * 0.3 }
    let microphone = reference.map { $0 * 0.6 }
    canceller.tryUpdateReference(reference)
    var output = microphone
    for _ in 0..<30 { output = canceller.process(microphone) }
    let before = microphone.reduce(Float.zero) { $0 + $1 * $1 }
    let after = output.reduce(Float.zero) { $0 + $1 * $1 }
    #expect(after < before * 0.2)
}
