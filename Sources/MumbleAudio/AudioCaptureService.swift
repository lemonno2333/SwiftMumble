import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import OSLog

private let audioCaptureLogger = Logger(subsystem: "com.leo.SwiftMumble", category: "AudioCapture")

public enum AudioCaptureError: Error {
    case permissionDenied
    case unsupportedInputFormat
    case audioComponentUnavailable
    case coreAudio(OSStatus)
}

public final class AudioCaptureService: AudioCaptureBackend, @unchecked Sendable {
    public typealias FrameHandler = @Sendable ([Float]) -> Void

    private let lock = NSLock()
    private let configurationLock = NSLock()
    private let sampleCapacity = 8_192
    private let sampleStorage: UnsafeMutablePointer<Float>
    private var accumulator = AudioFrameAccumulator()
    private var frameHandler: FrameHandler?
    private var selectedDeviceID: AudioDeviceID?
    private var audioUnit: AudioUnit?
    private var isRunning = false
    private var callbackCount: UInt64 = 0
    private var deliveredFrameCount: UInt64 = 0

    public init() {
        sampleStorage = .allocate(capacity: sampleCapacity)
        sampleStorage.initialize(repeating: 0, count: sampleCapacity)
    }

    deinit {
        shutdown()
        sampleStorage.deinitialize(count: sampleCapacity)
        sampleStorage.deallocate()
    }

    public func selectDevice(_ deviceID: AudioDeviceID?) {
        configurationLock.withLock {
            guard selectedDeviceID != deviceID else { return }
            shutdownUnlocked()
            selectedDeviceID = deviceID
        }
    }

    public static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    public func start(frameHandler: @escaping FrameHandler) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }

        try configurationLock.withLock {
            stopUnlocked()
            lock.withLock { self.frameHandler = frameHandler }
            do {
                try prepareUnlocked()
                guard let unit = audioUnit else { throw AudioCaptureError.audioComponentUnavailable }
                let start = ContinuousClock.now
                try Self.check(AudioOutputUnitStart(unit))
                isRunning = true
                let duration = start.duration(to: .now)
                audioCaptureLogger.notice("AUHAL input started in \(String(describing: duration), privacy: .public)")
                AudioDiagnostics.shared.record("capture.start duration=\(duration)")
            } catch {
                lock.withLock { self.frameHandler = nil }
                throw error
            }
        }
    }

    /// Initializes the AUHAL input graph without starting microphone capture.
    /// This removes most cold-start work from the first push-to-talk press.
    public func prepare() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }
        try configurationLock.withLock { try prepareUnlocked() }
    }

    private func prepareUnlocked() throws {
        guard audioUnit == nil else { return }

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            lock.withLock { self.frameHandler = nil }
            throw AudioCaptureError.audioComponentUnavailable
        }

        var unit: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &unit))
        guard let unit else {
            lock.withLock { self.frameHandler = nil }
            throw AudioCaptureError.audioComponentUnavailable
        }

        do {
            var enabled: UInt32 = 1
            try Self.check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                1,
                &enabled,
                UInt32(MemoryLayout<UInt32>.size)
            ))

            var disabled: UInt32 = 0
            try Self.check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,
                &disabled,
                UInt32(MemoryLayout<UInt32>.size)
            ))

            var deviceID = try selectedDeviceID ?? Self.defaultInputDeviceID()
            try Self.check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            ))

            var format = AudioStreamBasicDescription(
                mSampleRate: 48_000,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
                mFramesPerPacket: 1,
                mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
                mChannelsPerFrame: 1,
                mBitsPerChannel: 32,
                mReserved: 0
            )
            try Self.check(AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &format,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ))

            var callback = AURenderCallbackStruct(
                inputProc: audioCaptureInputCallback,
                inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
            )
            try Self.check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ))

            try Self.check(AudioUnitInitialize(unit))
            audioUnit = unit
        } catch {
            audioUnit = nil
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    public func stop() {
        configurationLock.withLock { stopUnlocked() }
    }

    private func stopUnlocked() {
        if isRunning, let unit = audioUnit {
            AudioOutputUnitStop(unit)
        }
        isRunning = false
        AudioDiagnostics.shared.record("capture.stop callbacks=\(callbackCount) delivered=\(deliveredFrameCount)")
        // `frameHandler` and `accumulator` are both touched on the realtime
        // capture thread, so clear them under the same lightweight lock the
        // callback uses rather than relying on `configurationLock` alone.
        lock.withLock {
            accumulator.reset()
            frameHandler = nil
        }
    }

    public func shutdown() {
        configurationLock.withLock { shutdownUnlocked() }
    }

    private func shutdownUnlocked() {
        stopUnlocked()
        guard let unit = audioUnit else { return }
        audioUnit = nil
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
    }

    fileprivate func capture(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard isRunning, let unit = audioUnit, frameCount <= sampleCapacity else { return noErr }

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: frameCount * UInt32(MemoryLayout<Float>.size),
                mData: sampleStorage
            )
        )
        let status = AudioUnitRender(unit, flags, timestamp, 1, frameCount, &bufferList)
        guard status == noErr else { return status }
        callbackCount &+= 1

        let samples = Array(UnsafeBufferPointer(start: sampleStorage, count: Int(frameCount)))
        // Snapshot the handler under the same lock that guards the accumulator so
        // a concurrent start/stop can't release the closure's context mid-call
        // (an ARC refcount race that could otherwise use-after-free).
        let (frames, handler) = lock.withLock { (accumulator.append(samples), frameHandler) }
        guard let handler else { return noErr }
        for frame in frames {
            deliveredFrameCount &+= 1
            handler(frame)
        }
        return noErr
    }

    private static func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ))
        return deviceID
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioCaptureError.coreAudio(status) }
    }
}

private let audioCaptureInputCallback: AURenderCallback = {
    reference, flags, timestamp, _, frameCount, _ in
    let service = Unmanaged<AudioCaptureService>.fromOpaque(reference).takeUnretainedValue()
    return service.capture(flags: flags, timestamp: timestamp, frameCount: frameCount)
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
