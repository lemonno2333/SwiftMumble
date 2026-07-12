import Foundation
import Testing
@testable import MumbleProtocol

@Test func ocb2MatchesUpstreamDraftVector() throws {
    let key = Array(UInt8(0)...UInt8(15))
    let empty = try MumbleOCB2.encrypt(plaintext: [], nonce: key, key: key)
    #expect(empty.tag == [
        0xbf, 0x31, 0x08, 0x13, 0x07, 0x73, 0xad, 0x5e,
        0xc7, 0x0e, 0xc6, 0x9e, 0x78, 0x75, 0xa7, 0xb0
    ])

    let source = Array(UInt8(0)...UInt8(39))
    let result = try MumbleOCB2.encrypt(plaintext: source, nonce: key, key: key)
    #expect(result.tag == [
        0x9d, 0xb0, 0xcd, 0xf8, 0x80, 0xf7, 0x3e, 0x3e,
        0x10, 0xd4, 0xeb, 0x32, 0x17, 0x76, 0x66, 0x88
    ])
    #expect(result.ciphertext == [
        0xf7, 0x5d, 0x6b, 0xc8, 0xb4, 0xdc, 0x8d, 0x66, 0xb8, 0x36,
        0xa2, 0xb0, 0x8b, 0x32, 0xa6, 0x36, 0x9f, 0x1c, 0xd3, 0xc5,
        0x22, 0x8d, 0x79, 0xfd, 0x6c, 0x26, 0x7f, 0x5f, 0x6a, 0xa7,
        0xb2, 0x31, 0xc7, 0xdf, 0xb9, 0xd5, 0x99, 0x51, 0xae, 0x9c
    ])
}

@Test func cryptStateAuthenticatesAndRejectsReplay() throws {
    let key = Data(0..<16)
    let clientNonce = Data(repeating: 0x55, count: 16)
    let serverNonce = Data(repeating: 0x33, count: 16)
    let client = try MumbleCryptState(key: key, clientNonce: clientNonce, serverNonce: serverNonce)
    let server = try MumbleCryptState(key: key, clientNonce: serverNonce, serverNonce: clientNonce)
    let plaintext = Data("mumble-udp".utf8)

    let encrypted = try client.encrypt(plaintext)
    #expect(try server.decrypt(encrypted) == plaintext)
    #expect(try server.decrypt(encrypted) == nil)

    var corrupted = try client.encrypt(plaintext)
    corrupted[corrupted.index(before: corrupted.endIndex)] ^= 1
    #expect(try server.decrypt(corrupted) == nil)
}
