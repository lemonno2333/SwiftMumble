import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Full-duplex audio backend built on `kAudioUnitSubType_VoiceProcessingIO`,
/// which gives system echo cancellation and automatic gain control through a
/// single Audio Unit that owns both capture and playback.
///
/// This is the shared-backend prototype called for by the R5 audio plan. It is
/// opt-in: the app defaults to the two independent AUHAL services (which the
/// P0/P1 realtime rework validated) and only routes through this unit when the
/// user enables system voice processing. Because VPIO manages input and output
/// on one device pair, per-app input/output device selection is intentionally
/// not offered while it is active — it follows the system default like other
/// VoiceProcessingIO clients (FaceTime, etc.).
///
/// `captureSink` is invoked with 10 ms mono frames from the mic. Playback is
/// pulled from the same ring buffers as `AudioPlaybackService`, so the mix
/// clock drives it identically.
public final class VoiceProcessingAudioUnit: @unchecked Sendable {
    public enum Failure: Error {
        case audioComponentUnavailable
        case coreAudio(OSStatus)
    }

    private let lock = NSLock()
    /// Lightweight lock for the realtime capture path only. Kept separate from
    /// `lock` (which serializes start/stop/shutdown while calling blocking Core
    /// Audio APIs) so the input callback never blocks on the heavier config
    /// lock. Mirrors `AudioCaptureService`'s dedicated accumulator lock. Guards
    /// `accumulator` and `captureSink`, which are otherwise mutated from both
    /// the realtime thread and the control thread.
    private let captureLock = NSLock()
    private let ring = AudioSampleRingBuffer(capacity: 48_000 * 2)
    private let overlayRing = AudioSampleRingBuffer(capacity: 48_000)

    private let renderScratchCapacity = 8_192
    private let renderScratch: UnsafeMutablePointer<Float>
    private let captureScratchCapacity = 8_192
    private let captureScratch: UnsafeMutablePointer<Float>
    private var accumulator = AudioFrameAccumulator()

    private var audioUnit: AudioUnit?
    private var isRunning = false
    private var captureSink: (@Sendable ([Float]) -> Void)?

    public init() {
        renderScratch = .allocate(capacity: renderScratchCapacity)
        renderScratch.initialize(repeating: 0, count: renderScratchCapacity)
        captureScratch = .allocate(capacity: captureScratchCapacity)
        captureScratch.initialize(repeating: 0, count: captureScratchCapacity)
    }

    deinit {
        shutdown()
        renderScratch.deinitialize(count: renderScratchCapacity)
        renderScratch.deallocate()
        captureScratch.deinitialize(count: captureScratchCapacity)
        captureScratch.deallocate()
    }

    // MARK: - Lifecycle

    /// Installs the microphone sink and starts the full-duplex unit. Requires a
    /// prior microphone permission grant (the caller handles the prompt).
    public func start(captureSink: @escaping @Sendable ([Float]) -> Void) throws {
        try lock.withLock {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                throw Failure.coreAudio(OSStatus(kAudioServicesUnsupportedPropertyError))
            }
            captureLock.withLock { self.captureSink = captureSink }
            try prepareUnlocked()
            guard let audioUnit else { throw Failure.audioComponentUnavailable }
            try Self.check(AudioOutputUnitStart(audioUnit))
            isRunning = true
            AudioDiagnostics.shared.record("vpio.start")
        }
    }

    public func stop() {
        lock.withLock {
            if isRunning, let audioUnit { AudioOutputUnitStop(audioUnit) }
            isRunning = false
            captureLock.withLock {
                captureSink = nil
                accumulator.reset()
            }
            ring.reset()
            overlayRing.reset()
            AudioDiagnostics.shared.record("vpio.stop")
        }
    }

    public func shutdown() {
        lock.withLock {
            if isRunning, let audioUnit { AudioOutputUnitStop(audioUnit) }
            isRunning = false
            captureLock.withLock { captureSink = nil }
            if let audioUnit {
                AudioUnitUninitialize(audioUnit)
                AudioComponentInstanceDispose(audioUnit)
            }
            audioUnit = nil
        }
    }

    // MARK: - Playback surface (mirrors AudioPlaybackService)

    public var bufferedSampleCount: Int { ring.availableSampleCount }
    public func enqueue(samples: [Float]) { ring.enqueue(samples) }
    public func enqueue(samples: UnsafePointer<Float>, count: Int) { ring.enqueue(samples, count: count) }
    public func enqueueOverlay(samples: [Float]) { overlayRing.enqueue(samples) }
    public func setMuted(_ muted: Bool) { ring.setMuted(muted); overlayRing.setMuted(muted) }

    // MARK: - Realtime callbacks

    /// Output bus 0 render: copy the mixed ring into the speaker buffers.
    fileprivate func render(frameCount: UInt32, outputData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        guard isRunning, frameCount <= renderScratchCapacity else {
            for buffer in UnsafeMutableAudioBufferListPointer(outputData) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }
        let count = Int(frameCount)
        ring.render(into: renderScratch, count: count)
        overlayRing.mix(into: renderScratch, count: count)
        for buffer in UnsafeMutableAudioBufferListPointer(outputData) {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            if channels == 1 {
                data.update(from: renderScratch, count: count)
            } else {
                for frame in 0..<count {
                    for channel in 0..<channels { data[frame * channels + channel] = renderScratch[frame] }
                }
            }
        }
        return noErr
    }

    /// Input bus 1 notify: pull the (echo-cancelled) mic frames and forward
    /// them as 10 ms mono frames.
    fileprivate func capture(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard isRunning, let audioUnit, frameCount <= captureScratchCapacity else { return noErr }
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: frameCount * UInt32(MemoryLayout<Float>.size),
                mData: captureScratch
            )
        )
        let status = AudioUnitRender(audioUnit, flags, timestamp, 1, frameCount, &bufferList)
        guard status == noErr else { return status }
        // Snapshot the sink and slice the accumulator under captureLock so a
        // concurrent stop()/shutdown() can't release the closure mid-call (ARC
        // refcount race) or mutate the accumulator's storage from another thread.
        let samples = Array(UnsafeBufferPointer(start: captureScratch, count: Int(frameCount)))
        let (sink, frames): ((@Sendable ([Float]) -> Void)?, [[Float]]) = captureLock.withLock {
            (captureSink, accumulator.append(samples))
        }
        guard let sink else { return noErr }
        for frame in frames { sink(frame) }
        return noErr
    }

    // MARK: - Configuration

    private func prepareUnlocked() throws {
        guard audioUnit == nil else { return }
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw Failure.audioComponentUnavailable
        }
        var unit: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &unit))
        guard let unit else { throw Failure.audioComponentUnavailable }

        do {
            var enable: UInt32 = 1
            // Enable input (bus 1) and output (bus 0).
            try Self.check(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                &enable, UInt32(MemoryLayout<UInt32>.size)
            ))
            try Self.check(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                &enable, UInt32(MemoryLayout<UInt32>.size)
            ))

            var streamFormat = AudioStreamBasicDescription(
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
            // Mic frames delivered to us (input scope of bus 1 = output side).
            try Self.check(AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ))
            // Frames we render for playback (input scope of bus 0).
            try Self.check(AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ))

            // System voice processing on; let the OS run AGC.
            var bypass: UInt32 = 0
            _ = AudioUnitSetProperty(
                unit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0,
                &bypass, UInt32(MemoryLayout<UInt32>.size)
            )
            var agc: UInt32 = 1
            _ = AudioUnitSetProperty(
                unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0,
                &agc, UInt32(MemoryLayout<UInt32>.size)
            )

            var renderCallback = AURenderCallbackStruct(
                inputProc: voiceProcessingRenderCallback,
                inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
            )
            try Self.check(AudioUnitSetProperty(
                unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ))
            var inputCallback = AURenderCallbackStruct(
                inputProc: voiceProcessingInputCallback,
                inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
            )
            try Self.check(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                &inputCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ))

            try Self.check(AudioUnitInitialize(unit))
            audioUnit = unit
        } catch {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw Failure.coreAudio(status) }
    }
}

private let voiceProcessingRenderCallback: AURenderCallback = {
    reference, _, _, _, frameCount, outputData in
    let unit = Unmanaged<VoiceProcessingAudioUnit>.fromOpaque(reference).takeUnretainedValue()
    guard let outputData else { return noErr }
    return unit.render(frameCount: frameCount, outputData: outputData)
}

private let voiceProcessingInputCallback: AURenderCallback = {
    reference, flags, timestamp, _, frameCount, _ in
    let unit = Unmanaged<VoiceProcessingAudioUnit>.fromOpaque(reference).takeUnretainedValue()
    return unit.capture(flags: flags, timestamp: timestamp, frameCount: frameCount)
}
