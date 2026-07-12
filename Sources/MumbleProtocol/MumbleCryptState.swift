import CommonCrypto
import Foundation

public enum MumbleCryptError: Error, Equatable {
    case invalidKeyOrNonceLength
    case aesFailure(Int32)
}

public struct MumbleCryptStats: Equatable, Sendable {
    public var good: UInt32 = 0
    public var late: UInt32 = 0
    public var lost: UInt32 = 0
}

public final class MumbleCryptState: @unchecked Sendable {
    private let lock = NSLock()
    private let key: [UInt8]
    private var encryptNonce: [UInt8]
    private var decryptNonce: [UInt8]
    private var decryptHistory = [UInt8](repeating: 0, count: 256)
    private var currentStats = MumbleCryptStats()

    public init(key: Data, clientNonce: Data, serverNonce: Data) throws {
        guard key.count == 16, clientNonce.count == 16, serverNonce.count == 16 else {
            throw MumbleCryptError.invalidKeyOrNonceLength
        }
        self.key = Array(key)
        encryptNonce = Array(clientNonce)
        decryptNonce = Array(serverNonce)
    }

    public var stats: MumbleCryptStats {
        lock.withLock { currentStats }
    }

    public var clientNonce: Data {
        lock.withLock { Data(encryptNonce) }
    }

    public func updateServerNonce(_ nonce: Data) throws {
        guard nonce.count == 16 else { throw MumbleCryptError.invalidKeyOrNonceLength }
        lock.withLock {
            decryptNonce = Array(nonce)
        }
    }

    public func encrypt(_ plaintext: Data) throws -> Data {
        try lock.withLock {
            incrementLittleEndian(&encryptNonce)
            let result = try MumbleOCB2.encrypt(
                plaintext: Array(plaintext),
                nonce: encryptNonce,
                key: key
            )

            var packet = Data([encryptNonce[0], result.tag[0], result.tag[1], result.tag[2]])
            packet.append(contentsOf: result.ciphertext)
            return packet
        }
    }

    public func decrypt(_ packet: Data) throws -> Data? {
        try lock.withLock {
            guard packet.count >= 4 else { return nil }
            let bytes = Array(packet)
            let savedNonce = decryptNonce
            let ivByte = bytes[0]
            var restore = false
            var late = 0
            var lost = 0

            if decryptNonce[0] &+ 1 == ivByte {
                if ivByte > decryptNonce[0] {
                    decryptNonce[0] = ivByte
                } else if ivByte < decryptNonce[0] {
                    decryptNonce[0] = ivByte
                    incrementCarry(&decryptNonce, startingAt: 1)
                } else {
                    return nil
                }
            } else {
                var difference = Int(ivByte) - Int(decryptNonce[0])
                if difference > 128 { difference -= 256 }
                else if difference < -128 { difference += 256 }

                if ivByte < decryptNonce[0], difference > -30, difference < 0 {
                    late = 1
                    lost = -1
                    decryptNonce[0] = ivByte
                    restore = true
                } else if ivByte > decryptNonce[0], difference > -30, difference < 0 {
                    late = 1
                    lost = -1
                    decryptNonce[0] = ivByte
                    decrementCarry(&decryptNonce, startingAt: 1)
                    restore = true
                } else if ivByte > decryptNonce[0], difference > 0 {
                    lost = Int(ivByte) - Int(decryptNonce[0]) - 1
                    decryptNonce[0] = ivByte
                } else if ivByte < decryptNonce[0], difference > 0 {
                    lost = 256 - Int(decryptNonce[0]) + Int(ivByte) - 1
                    decryptNonce[0] = ivByte
                    incrementCarry(&decryptNonce, startingAt: 1)
                } else {
                    return nil
                }

                if decryptHistory[Int(decryptNonce[0])] == decryptNonce[1] {
                    decryptNonce = savedNonce
                    return nil
                }
            }

            let result = try MumbleOCB2.decrypt(
                ciphertext: Array(bytes.dropFirst(4)),
                nonce: decryptNonce,
                key: key
            )
            guard Array(result.tag.prefix(3)) == Array(bytes[1...3]) else {
                decryptNonce = savedNonce
                return nil
            }

            decryptHistory[Int(decryptNonce[0])] = decryptNonce[1]
            if restore { decryptNonce = savedNonce }

            currentStats.good &+= 1
            adjust(&currentStats.late, by: late)
            adjust(&currentStats.lost, by: lost)
            return Data(result.plaintext)
        }
    }

    private func adjust(_ value: inout UInt32, by difference: Int) {
        if difference > 0 {
            value &+= UInt32(difference)
        } else if difference < 0, value > UInt32(-difference) {
            value -= UInt32(-difference)
        }
    }

    private func incrementLittleEndian(_ bytes: inout [UInt8]) {
        for index in bytes.indices {
            bytes[index] &+= 1
            if bytes[index] != 0 { break }
        }
    }

    private func incrementCarry(_ bytes: inout [UInt8], startingAt index: Int) {
        guard index < bytes.count else { return }
        for position in index..<bytes.count {
            bytes[position] &+= 1
            if bytes[position] != 0 { break }
        }
    }

    private func decrementCarry(_ bytes: inout [UInt8], startingAt index: Int) {
        guard index < bytes.count else { return }
        for position in index..<bytes.count {
            let previous = bytes[position]
            bytes[position] &-= 1
            if previous != 0 { break }
        }
    }
}

enum MumbleOCB2 {
    static func encrypt(
        plaintext: [UInt8],
        nonce: [UInt8],
        key: [UInt8],
        mitigateXEXStar: Bool = true
    ) throws -> (ciphertext: [UInt8], tag: [UInt8]) {
        var delta = try aes(.encrypt, block: nonce, key: key)
        var checksum = zeroBlock
        var ciphertext = [UInt8](repeating: 0, count: plaintext.count)
        var offset = 0

        while plaintext.count - offset > 16 {
            var flipBit = false
            if plaintext.count - offset - 16 <= 16 {
                flipBit = plaintext[offset..<(offset + 15)].allSatisfy { $0 == 0 }
            }

            double(&delta)
            let plainBlock = Array(plaintext[offset..<(offset + 16)])
            var temporary = xor(delta, plainBlock)
            if flipBit, mitigateXEXStar { temporary[0] ^= 1 }
            temporary = try aes(.encrypt, block: temporary, key: key)
            let encryptedBlock = xor(delta, temporary)
            ciphertext.replaceSubrange(offset..<(offset + 16), with: encryptedBlock)
            checksum = xor(checksum, plainBlock)
            if flipBit, mitigateXEXStar { checksum[0] ^= 1 }
            offset += 16
        }

        double(&delta)
        let remaining = plaintext.count - offset
        var temporary = zeroBlock
        temporary[15] = UInt8(remaining * 8)
        temporary = xor(temporary, delta)
        let pad = try aes(.encrypt, block: temporary, key: key)
        temporary = pad
        for index in 0..<remaining {
            temporary[index] = plaintext[offset + index]
            ciphertext[offset + index] = pad[index] ^ temporary[index]
        }
        checksum = xor(checksum, temporary)

        triple(&delta)
        let tag = try aes(.encrypt, block: xor(delta, checksum), key: key)
        return (ciphertext, tag)
    }

    static func decrypt(
        ciphertext: [UInt8],
        nonce: [UInt8],
        key: [UInt8]
    ) throws -> (plaintext: [UInt8], tag: [UInt8]) {
        var delta = try aes(.encrypt, block: nonce, key: key)
        var checksum = zeroBlock
        var plaintext = [UInt8](repeating: 0, count: ciphertext.count)
        var offset = 0

        while ciphertext.count - offset > 16 {
            double(&delta)
            let encryptedBlock = Array(ciphertext[offset..<(offset + 16)])
            var temporary = xor(delta, encryptedBlock)
            temporary = try aes(.decrypt, block: temporary, key: key)
            let plainBlock = xor(delta, temporary)
            plaintext.replaceSubrange(offset..<(offset + 16), with: plainBlock)
            checksum = xor(checksum, plainBlock)
            offset += 16
        }

        double(&delta)
        let remaining = ciphertext.count - offset
        var temporary = zeroBlock
        temporary[15] = UInt8(remaining * 8)
        temporary = xor(temporary, delta)
        let pad = try aes(.encrypt, block: temporary, key: key)
        temporary = pad
        for index in 0..<remaining {
            temporary[index] = ciphertext[offset + index] ^ pad[index]
            plaintext[offset + index] = temporary[index]
        }
        checksum = xor(checksum, temporary)

        triple(&delta)
        let tag = try aes(.encrypt, block: xor(delta, checksum), key: key)
        return (plaintext, tag)
    }

    private enum AESOperation {
        case encrypt
        case decrypt
    }

    private static let zeroBlock = [UInt8](repeating: 0, count: 16)

    private static func aes(_ operation: AESOperation, block: [UInt8], key: [UInt8]) throws -> [UInt8] {
        precondition(block.count == 16 && key.count == 16)
        var output = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = key.withUnsafeBytes { keyBytes in
            block.withUnsafeBytes { inputBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCCrypt(
                        operation == .encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        inputBytes.baseAddress,
                        block.count,
                        outputBytes.baseAddress,
                        16,
                        &moved
                    )
                }
            }
        }
        guard status == kCCSuccess, moved == 16 else {
            throw MumbleCryptError.aesFailure(status)
        }
        return output
    }

    private static func xor(_ left: [UInt8], _ right: [UInt8]) -> [UInt8] {
        zip(left, right).map(^)
    }

    private static func double(_ block: inout [UInt8]) {
        let carry = block[0] >> 7
        for index in 0..<15 {
            block[index] = block[index] << 1 | block[index + 1] >> 7
        }
        block[15] = block[15] << 1 ^ (carry == 0 ? 0 : 0x87)
    }

    private static func triple(_ block: inout [UInt8]) {
        let original = block
        double(&block)
        block = xor(block, original)
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
