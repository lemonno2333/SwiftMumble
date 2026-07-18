import CoreAudio
import Darwin
import Foundation

/// Playback surface the app and the mix clock drive. Implemented by the
/// standalone AUHAL `AudioPlaybackService` (default) and by the
/// voice-processing full-duplex unit's playback side (opt-in).
public protocol AudioPlaybackBackend: AnyObject, Sendable {
    func start() throws
    func stop()
    func selectDevice(_ deviceID: AudioDeviceID?) throws
    func enqueue(samples: [Float]) throws
    func enqueue(samples: UnsafePointer<Float>, count: Int)
    func enqueueOverlay(samples: [Float])
    func setMuted(_ muted: Bool)
    var bufferedSampleCount: Int { get }
    func undoSystemVoiceDucking()
}

/// Capture surface delivering 480-sample (10 ms) microphone frames.
public protocol AudioCaptureBackend: AnyObject, Sendable {
    func start(frameHandler: @escaping @Sendable ([Float]) -> Void) throws
    func prepare() throws
    func stop()
    func shutdown()
    func selectDevice(_ deviceID: AudioDeviceID?)
}

/// Matches the workaround used by official Mumble and Mozilla cubeb for macOS
/// voice-capture sessions that automatically duck the output device.
public enum AudioOutputDucking {
    public static func undo(deviceID: AudioDeviceID) {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AudioDeviceDuck") else {
            AudioDiagnostics.shared.record("playback.unduck unavailable")
            return
        }
        typealias AudioDeviceDuckFunction = @convention(c) (
            AudioDeviceID,
            Float32,
            UnsafePointer<AudioTimeStamp>?,
            Float32
        ) -> OSStatus
        let audioDeviceDuck = unsafeBitCast(symbol, to: AudioDeviceDuckFunction.self)
        let status = audioDeviceDuck(deviceID, 1, nil, 0.5)
        AudioDiagnostics.shared.record("playback.unduck device=\(deviceID) status=\(status)")
    }
}
