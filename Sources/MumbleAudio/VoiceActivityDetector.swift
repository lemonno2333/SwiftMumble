import Foundation

public enum AudioLevelMeter {
    public static func decibels(samples: [Float], floor: Double = -80) -> Double {
        guard !samples.isEmpty else { return floor }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        guard meanSquare > 0 else { return floor }
        return max(floor, min(0, 10 * log10(meanSquare)))
    }
}

public struct VoiceActivityGate: Equatable, Sendable {
    public let hangoverFrames: Int
    public private(set) var remainingHangoverFrames = 0
    public private(set) var isOpen = false

    public init(hangoverFrames: Int = 30) {
        precondition(hangoverFrames >= 0)
        self.hangoverFrames = hangoverFrames
    }

    @discardableResult
    public mutating func process(levelDB: Double, thresholdDB: Double) -> Bool {
        if levelDB >= thresholdDB {
            remainingHangoverFrames = hangoverFrames
            isOpen = true
        } else if remainingHangoverFrames > 0 {
            remainingHangoverFrames -= 1
            isOpen = true
        } else {
            isOpen = false
        }
        return isOpen
    }

    public mutating func reset() {
        remainingHangoverFrames = 0
        isOpen = false
    }
}

/// Exponential moving average for the microphone dBFS level. Rises quickly so
/// speech onset is not clipped, and falls slowly so the meter and the gate do
/// not flicker between frames.
public struct LevelSmoother: Equatable, Sendable {
    public let attack: Double
    public let release: Double
    public private(set) var value: Double
    private var hasSample = false

    public init(attack: Double = 0.6, release: Double = 0.15, initialValue: Double = -80) {
        precondition(attack > 0 && attack <= 1)
        precondition(release > 0 && release <= 1)
        self.attack = attack
        self.release = release
        value = initialValue
    }

    @discardableResult
    public mutating func process(levelDB: Double) -> Double {
        guard hasSample else {
            value = levelDB
            hasSample = true
            return value
        }
        let coefficient = levelDB > value ? attack : release
        value += (levelDB - value) * coefficient
        return value
    }

    public mutating func reset(to level: Double = -80) {
        value = level
        hasSample = false
    }
}

/// Tracks the ambient noise floor from level samples taken while no speech is
/// present, and recommends an activation threshold a fixed margin above it.
/// Falls fast toward quieter levels and rises slowly, so a brief noise burst
/// does not permanently raise the estimate.
public struct NoiseFloorTracker: Equatable, Sendable {
    public let marginDB: Double
    public let minimumFloorDB: Double
    public let fallCoefficient: Double
    public let riseCoefficient: Double
    public private(set) var estimatedFloorDB: Double
    private var hasSample = false

    public init(
        marginDB: Double = 9,
        minimumFloorDB: Double = -75,
        fallCoefficient: Double = 0.4,
        riseCoefficient: Double = 0.02,
        initialFloorDB: Double = -60
    ) {
        precondition(fallCoefficient > 0 && fallCoefficient <= 1)
        precondition(riseCoefficient > 0 && riseCoefficient <= 1)
        self.marginDB = marginDB
        self.minimumFloorDB = minimumFloorDB
        self.fallCoefficient = fallCoefficient
        self.riseCoefficient = riseCoefficient
        estimatedFloorDB = max(minimumFloorDB, initialFloorDB)
    }

    @discardableResult
    public mutating func observeSilence(levelDB: Double) -> Double {
        let clamped = max(minimumFloorDB, levelDB)
        guard hasSample else {
            estimatedFloorDB = clamped
            hasSample = true
            return estimatedFloorDB
        }
        let coefficient = clamped < estimatedFloorDB ? fallCoefficient : riseCoefficient
        estimatedFloorDB += (clamped - estimatedFloorDB) * coefficient
        return estimatedFloorDB
    }

    /// Suggested activation threshold: the floor plus the margin, kept inside
    /// the slider's usable range.
    public var recommendedThresholdDB: Double {
        min(-5, max(-70, estimatedFloorDB + marginDB))
    }

    public mutating func reset(to level: Double = -60) {
        estimatedFloorDB = max(minimumFloorDB, level)
        hasSample = false
    }
}
