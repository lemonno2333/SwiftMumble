import CryptoKit
import Foundation

public struct MumbleCertificateFingerprint: Equatable, Hashable, Sendable {
    public let bytes: Data

    public init(certificateDER: Data) {
        bytes = Data(SHA256.hash(data: certificateDER))
    }

    public init?(bytes: Data) {
        guard bytes.count == 32 else { return nil }
        self.bytes = bytes
    }

    public init?(hex: String) {
        let normalized = hex
            .lowercased()
            .filter { $0.isHexDigit }
        guard normalized.count == 64 else { return nil }

        var data = Data(capacity: 32)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        bytes = data
    }

    public var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public var formatted: String {
        stride(from: 0, to: hex.count, by: 2)
            .map { offset -> String in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 2)
                return String(hex[start..<end])
            }
            .joined(separator: ":")
    }
}

public enum MumbleCertificatePinEvaluation: Equatable, Sendable {
    case notPinned
    case match
    case mismatch(expected: MumbleCertificateFingerprint, actual: MumbleCertificateFingerprint)
    case invalidPinnedFingerprint
}

public enum MumbleCertificatePinEvaluator {
    public static func evaluate(
        actual: MumbleCertificateFingerprint,
        pinnedSHA256: Data?
    ) -> MumbleCertificatePinEvaluation {
        guard let pinnedSHA256 else { return .notPinned }
        guard let expected = MumbleCertificateFingerprint(bytes: pinnedSHA256) else {
            return .invalidPinnedFingerprint
        }
        return expected == actual ? .match : .mismatch(expected: expected, actual: actual)
    }
}
