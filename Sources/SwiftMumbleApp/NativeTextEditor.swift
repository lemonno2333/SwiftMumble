import AppKit
import SwiftUI

struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var maximumHeight: CGFloat = 92
    var onSubmit: (() -> Void)?
    var onComplete: (() -> Void)?
    var onHistoryUp: (() -> Void)?
    var onHistoryDown: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.string = text
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.updateHeight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
        }
        context.coordinator.updateHeight()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        weak var textView: NSTextView?

        init(parent: NativeTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            updateHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                guard let onSubmit = parent.onSubmit,
                      NSApp.currentEvent?.modifierFlags.contains(.shift) != true else { return false }
                onSubmit()
                return true
            case #selector(NSResponder.insertTab(_:)):
                guard let onComplete = parent.onComplete else { return false }
                onComplete()
                return true
            case #selector(NSResponder.moveUp(_:)):
                guard let onHistoryUp = parent.onHistoryUp else { return false }
                onHistoryUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard let onHistoryDown = parent.onHistoryDown else { return false }
                onHistoryDown()
                return true
            default:
                return false
            }
        }

        func updateHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
            let height = min(parent.maximumHeight, max(24, ceil(usedHeight)))
            guard parent.contentHeight != height else { return }
            DispatchQueue.main.async { [weak self] in self?.parent.contentHeight = height }
        }
    }
}
