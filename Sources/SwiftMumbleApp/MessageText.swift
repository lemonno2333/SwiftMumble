import AppKit
import SwiftUI
import SwiftSoup

/// Renders a Mumble text message for display. Mumble messages may contain a
/// curated subset of HTML; plain messages are shown as-is. Parsed links are
/// preserved so SwiftUI's Text can make them tappable.
@MainActor
enum MessageText {
    private static let maximumEmbeddedImageBytes = 2_000_000
    private static let sanitizedHTMLCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 500
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()
    private static let nativeAttributedCache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 300
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()

    static func sanitizedHTML(from message: String) -> String {
        let cacheKey = message as NSString
        if let cached = sanitizedHTMLCache.object(forKey: cacheKey) { return cached as String }
        let sanitized: String
        if !looksLikeHTML(message) {
            sanitized = escapedHTML(message)
        } else {
            do {
                let whitelist = try Whitelist.relaxed()
                try whitelist.removeProtocols("img", "src", "http", "https")
                try whitelist.addProtocols("img", "src", "data")
                try whitelist.addProtocols("a", "href", "mumble")
                let cleaned = try SwiftSoup.clean(message, whitelist) ?? ""
                let document = try SwiftSoup.parseBodyFragment(cleaned, "")
                for image in try document.select("img[src]").array() {
                    let source = try image.attr("src")
                    guard isAllowedEmbeddedImage(source) else {
                        try image.remove()
                        continue
                    }
                }
                sanitized = try document.body()?.html() ?? ""
            } catch {
                sanitized = escapedHTML(message)
            }
        }
        sanitizedHTMLCache.setObject(
            sanitized as NSString,
            forKey: cacheKey,
            cost: message.utf8.count + sanitized.utf8.count
        )
        return sanitized
    }

    static func nativeAttributed(from message: String) -> NSAttributedString? {
        let cacheKey = message as NSString
        if let cached = nativeAttributedCache.object(forKey: cacheKey) { return cached }
        let source = sanitizedHTML(from: message)
        let wrapped = "<style>body{font:-apple-system-body;color:labelColor;margin:0}img{max-width:420px;height:auto}</style>\(source)"
        guard let data = wrapped.data(using: .utf8),
              let value = try? NSAttributedString(data: data, options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
              ], documentAttributes: nil) else { return nil }
        nativeAttributedCache.setObject(
            value,
            forKey: cacheKey,
            cost: data.count + value.length * MemoryLayout<unichar>.size
        )
        return value
    }

    static func attributed(from message: String) -> AttributedString {
        guard looksLikeHTML(message) else {
            return AttributedString(message)
        }
        guard let ns = nativeAttributed(from: message) else {
            return AttributedString(message)
        }
        var result = (try? AttributedString(ns, including: \.swiftUI)) ?? AttributedString(ns.string)
        // Trim the trailing newline the HTML importer commonly appends.
        while let last = result.characters.last, last == "\n" {
            result.removeSubrange(result.index(beforeCharacter: result.endIndex) ..< result.endIndex)
        }
        // Drop imported font sizes/colors so messages inherit the view's style.
        for run in result.runs {
            result[run.range].font = nil
            result[run.range].foregroundColor = nil
        }
        return result
    }

    static func plainText(from message: String) -> String {
        String(attributed(from: message).characters)
    }

    /// Whether a message's plain text mentions the given username as a whole
    /// word (case- and diacritic-insensitive), so "Leo" matches "hey Leo!" but
    /// not "Leopold".
    nonisolated static func mentions(_ plainText: String, username: String) -> Bool {
        guard !username.isEmpty else { return false }
        var searchRange = plainText.startIndex..<plainText.endIndex
        while let range = plainText.range(
            of: username,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        ) {
            let boundedBefore = range.lowerBound == plainText.startIndex
                || !isNameCharacter(plainText[plainText.index(before: range.lowerBound)])
            let boundedAfter = range.upperBound == plainText.endIndex
                || !isNameCharacter(plainText[range.upperBound])
            if boundedBefore && boundedAfter { return true }
            searchRange = range.upperBound..<plainText.endIndex
        }
        return false
    }

    private nonisolated static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    static func embeddedImages(from message: String) -> [(extension: String, data: Data)] {
        let pattern = #"data:image/(png|jpeg|gif);base64,([A-Za-z0-9+/=]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        return regex.matches(in: message, range: range).compactMap { match in
            guard let typeRange = Range(match.range(at: 1), in: message),
                  let dataRange = Range(match.range(at: 2), in: message),
                  let data = Data(base64Encoded: String(message[dataRange])) else { return nil }
            let type = message[typeRange].lowercased() == "jpeg" ? "jpg" : String(message[typeRange]).lowercased()
            return (type, data)
        }
    }

    @MainActor static func saveFirstEmbeddedImage(from message: String) {
        guard let image = embeddedImages(from: message).first else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "mumble-image.\(image.extension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? image.data.write(to: url, options: .atomic)
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        guard let open = text.firstIndex(of: "<") else { return false }
        let rest = text[text.index(after: open)...]
        // A tag name or closing slash right after '<' is a good enough signal.
        return rest.first.map { $0.isLetter || $0 == "/" } ?? false
    }

    private static func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func isAllowedEmbeddedImage(_ source: String) -> Bool {
        let prefixPattern = #"^data:image/(png|jpeg|gif);base64,"#
        guard let regex = try? NSRegularExpression(pattern: prefixPattern, options: .caseInsensitive) else {
            return false
        }
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: fullRange), match.range.location == 0,
              let payloadRange = Range(NSRange(location: match.range.length, length: fullRange.length - match.range.length), in: source),
              let data = Data(base64Encoded: String(source[payloadRange]), options: .ignoreUnknownCharacters) else {
            return false
        }
        return !data.isEmpty && data.count <= maximumEmbeddedImageBytes
    }

    static func resetCachesForTesting() {
        sanitizedHTMLCache.removeAllObjects()
        nativeAttributedCache.removeAllObjects()
    }
}

private extension AttributedString {
    func index(beforeCharacter i: Index) -> Index {
        characters.index(before: i)
    }
}
