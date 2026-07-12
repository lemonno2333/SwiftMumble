import AppKit
import Foundation

@MainActor
final class AudioCueService {
    enum Cue {
        case transmitStart
        case transmitStop
        case muted
        case unmuted
        case userJoined, userLeft, connected, disconnected
    }

    private var activeSounds: [NSSound] = []

    func play(_ cue: Cue) {
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
        guard let sound = NSSound(data: Self.waveData(frequencies: frequencies)) else { return }
        activeSounds.removeAll { !$0.isPlaying }
        activeSounds.append(sound)
        sound.play()
    }

    private static func waveData(frequencies: [Double]) -> Data {
        let sampleRate = 22_050
        let segmentSamples = Int(Double(sampleRate) * 0.07)
        var pcm = [Int16]()
        for frequency in frequencies {
            for index in 0 ..< segmentSamples {
                let envelope = sin(Double.pi * Double(index) / Double(segmentSamples))
                let sample = sin(2 * Double.pi * frequency * Double(index) / Double(sampleRate))
                pcm.append(Int16(sample * envelope * 5_000))
            }
        }
        var data = Data()
        let byteCount = UInt32(pcm.count * MemoryLayout<Int16>.size)
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + byteCount)
        data.appendASCII("WAVEfmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(byteCount)
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) { append(contentsOf: value.utf8) }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
