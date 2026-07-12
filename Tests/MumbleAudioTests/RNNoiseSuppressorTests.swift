import Foundation
import Testing
@testable import MumbleAudio

@Test func rnnoiseProcessesOneNativeFrameWithoutChangingItsShape() {
    let suppressor = RNNoiseSuppressor()
    let input = (0 ..< 480).map { index in
        Float(sin(Double(index) * 0.08) * 0.15)
    }

    let output = suppressor.process(input)

    #expect(output.count == input.count)
    #expect(output.allSatisfy { $0.isFinite && (-1 ... 1).contains($0) })
}

@Test func rnnoiseLeavesUnsupportedFrameSizesUntouched() {
    let suppressor = RNNoiseSuppressor()
    let samples: [Float] = [0.1, -0.2]
    #expect(suppressor.process(samples) == samples)
}
