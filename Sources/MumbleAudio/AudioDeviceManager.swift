import AudioToolbox
import CoreAudio
import Foundation

public struct AudioDeviceInfo: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let name: String
    public let isDefault: Bool

    public init(id: AudioDeviceID, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public enum AudioDeviceError: Error {
    case coreAudio(OSStatus)
    case audioUnitUnavailable
}

public enum AudioDeviceManager {
    public static func inputDevices() throws -> [AudioDeviceInfo] {
        try devices(scope: kAudioDevicePropertyScopeInput)
    }

    public static func outputDevices() throws -> [AudioDeviceInfo] {
        try devices(scope: kAudioDevicePropertyScopeOutput)
    }

    public static func select(_ deviceID: AudioDeviceID, on audioUnit: AudioUnit?) throws {
        guard let audioUnit else { throw AudioDeviceError.audioUnitUnavailable }
        var deviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw AudioDeviceError.coreAudio(status) }
    }

    private static func devices(scope: AudioObjectPropertyScope) throws -> [AudioDeviceInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else { throw AudioDeviceError.coreAudio(status) }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )
        guard status == noErr else { throw AudioDeviceError.coreAudio(status) }

        let defaultID = try defaultDevice(scope: scope)
        return try deviceIDs
            .filter { try hasStreams(deviceID: $0, scope: scope) }
            .map {
                AudioDeviceInfo(
                    id: $0,
                    name: try deviceName(deviceID: $0),
                    isDefault: $0 == defaultID
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func defaultDevice(scope: AudioObjectPropertyScope) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: scope == kAudioDevicePropertyScopeInput
                ? kAudioHardwarePropertyDefaultInputDevice
                : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else { throw AudioDeviceError.coreAudio(status) }
        return deviceID
    }

    private static func hasStreams(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func deviceName(deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { throw AudioDeviceError.coreAudio(status) }
        return name.takeUnretainedValue() as String
    }
}
