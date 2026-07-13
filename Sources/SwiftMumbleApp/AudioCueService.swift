import Foundation

final class AudioCueService {
    enum Cue {
        case transmitStart
        case transmitStop
        case muted
        case unmuted
        case userJoined, userLeft, connected, disconnected
    }

    func samples(for cue: Cue) -> [Float] {
        let frequencies: [Double]
        switch cue {
        case .transmitStart: frequencies = [660, 880]
        case .transmitStop: frequencies = [660, 440]
        case .muted: frequencies = [330, 220]
        case .unmuted: frequencies = [440, 660]
        case .userJoined: frequencies = [520, 700]
        case .userLeft: frequencies = [700, 420]
        case .connected: frequencies = [440, 660, 880]
        case .disconnected: frequencies = [660, 440, 260]
        }
        return Self.samples(frequencies: frequencies)
    }

    private static func samples(frequencies: [Double]) -> [Float] {
        let sampleRate = 48_000
        let segmentSamples = Int(Double(sampleRate) * 0.07)
        var pcm: [Float] = []
        pcm.reserveCapacity(segmentSamples * frequencies.count)
        for frequency in frequencies {
            for index in 0 ..< segmentSamples {
                let envelope = sin(Double.pi * Double(index) / Double(segmentSamples))
                let sample = sin(2 * Double.pi * frequency * Double(index) / Double(sampleRate))
                pcm.append(Float(sample * envelope * 0.15))
            }
        }
        return pcm
    }
}
