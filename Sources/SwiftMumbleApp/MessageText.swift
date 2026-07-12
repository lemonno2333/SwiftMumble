import AppKit
import SwiftUI

/// Renders a Mumble text message for display. Mumble messages may contain a
/// curated subset of HTML; plain messages are shown as-is. Parsed links are
/// preserved so SwiftUI's Text can make them tappable.
enum MessageText {
    static func attributed(from message: String) -> AttributedString {
        guard looksLikeHTML(message) else {
            return AttributedString(message)
        }
        guard let data = message.data(using: .utf8) else {
            return AttributedString(message)
        }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let ns = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
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
}

private extension AttributedString {
    func index(beforeCharacter i: Index) -> Index {
        characters.index(before: i)
    }
}
