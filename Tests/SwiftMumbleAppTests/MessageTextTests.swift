import Foundation
import Testing
@testable import SwiftMumbleApp

@MainActor
@Test func sanitizedHTMLRemovesRemoteResourcesAndDangerousTags() {
    MessageText.resetCachesForTesting()
    let html = """
    <p>Hello <a href="https://example.com">site</a></p>
    <img src="https://tracker.example/pixel.png">
    <script src="https://tracker.example/payload.js"></script>
    <div style="background-image:url(https://tracker.example/background.png)">content</div>
    """

    let cleaned = MessageText.sanitizedHTML(from: html)

    #expect(cleaned.contains("https://example.com"))
    #expect(!cleaned.contains("tracker.example"))
    #expect(!cleaned.contains("script"))
    #expect(!cleaned.contains("style="))
}

@MainActor
@Test func sanitizedHTMLKeepsSmallEmbeddedImages() {
    MessageText.resetCachesForTesting()
    let payload = Data([0x89, 0x50, 0x4e, 0x47]).base64EncodedString()
    let cleaned = MessageText.sanitizedHTML(
        from: "<p>image</p><img alt=\"sample\" src=\"data:image/png;base64,\(payload)\">"
    )

    #expect(cleaned.contains("data:image/png;base64"))
    #expect(cleaned.contains("alt=\"sample\""))
}

@MainActor
@Test func nativeAttributedMessagesCanBeReusedFromCache() throws {
    MessageText.resetCachesForTesting()
    let message = "<p>Hello <strong>cache</strong></p>"

    let first = try #require(MessageText.nativeAttributed(from: message))
    let second = try #require(MessageText.nativeAttributed(from: message))

    #expect(first === second)
    #expect(first.string.contains("Hello cache"))
}

@Test func mentionMatchesWholeWordCaseInsensitively() {
    #expect(MessageText.mentions("hey Leo, you there?", username: "leo"))
    #expect(MessageText.mentions("LEO!", username: "Leo"))
    #expect(MessageText.mentions("ping @Léo", username: "leo"))
}

@Test func mentionIgnoresSubstringsAndEmptyName() {
    #expect(!MessageText.mentions("Leopold joined", username: "Leo"))
    #expect(!MessageText.mentions("teleology", username: "Leo"))
    #expect(!MessageText.mentions("anything", username: ""))
}
