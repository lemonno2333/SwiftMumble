import CoreAudio
import Foundation

/// Adapts a single `VoiceProcessingAudioUnit` to the app's separate capture and
/// playback backend protocols, so the existing transmit/mix wiring can drive
/// the full-duplex unit without knowing it is shared.
///
/// The unit starts when capture starts (the app always monitors the mic while
/// connected in VAD/continuous mode, and on PTT press) and both surfaces share
/// its lifetime. Playback enqueues are always safe: they land in the ring even
/// before the unit is running and are heard once capture brings it up.
public final class VoiceProcessingBackend: @unchecked Sendable {
    private let unit = VoiceProcessingAudioUnit()

    public init() {}

    public var playback: AudioPlaybackBackend { PlaybackFace(unit: unit) }
    public var capture: AudioCaptureBackend { CaptureFace(unit: unit) }

    private final class PlaybackFace: AudioPlaybackBackend, @unchecked Sendable {
        let unit: VoiceProcessingAudioUnit
        init(unit: VoiceProcessingAudioUnit) { self.unit = unit }

        // The unit's lifetime is owned by the capture side; playback never
        // starts or stops it, only feeds its ring.
        func start() throws {}
        func stop() {}
        func selectDevice(_ deviceID: AudioDeviceID?) throws {}
        func enqueue(samples: [Float]) throws { unit.enqueue(samples: samples) }
        func enqueue(samples: UnsafePointer<Float>, count: Int) { unit.enqueue(samples: samples, count: count) }
        func enqueueOverlay(samples: [Float]) { unit.enqueueOverlay(samples: samples) }
        func setMuted(_ muted: Bool) { unit.setMuted(muted) }
        var bufferedSampleCount: Int { unit.bufferedSampleCount }
        // VPIO already ducks/unducks internally; nothing to undo.
        func undoSystemVoiceDucking() {}
    }

    private final class CaptureFace: AudioCaptureBackend, @unchecked Sendable {
        let unit: VoiceProcessingAudioUnit
        init(unit: VoiceProcessingAudioUnit) { self.unit = unit }

        func start(frameHandler: @escaping @Sendable ([Float]) -> Void) throws {
            try unit.start(captureSink: frameHandler)
        }
        // The full-duplex unit initializes on start; there is no cheaper warm-up.
        func prepare() throws {}
        func stop() { unit.stop() }
        func shutdown() { unit.shutdown() }
        // Device selection follows the system default under voice processing.
        func selectDevice(_ deviceID: AudioDeviceID?) {}
    }
}
