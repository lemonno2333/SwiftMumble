import AppKit
import SwiftUI

struct RichMessageView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        let source = html.contains("<") ? html : html.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let wrapped = "<style>body{font:-apple-system-body;color:labelColor;margin:0}img{max-width:420px;height:auto}</style>\(source)"
        guard let data = wrapped.data(using: .utf8),
              let value = try? NSAttributedString(data: data, options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
              ], documentAttributes: nil) else { view.string = html; return }
        view.textStorage?.setAttributedString(value)
    }
}
