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
    var onCompositionChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NativeComposerTextView()
        textView.compositionChanged = { [weak coordinator = context.coordinator] active in
            coordinator?.parent.onCompositionChange?(active)
        }
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
        context.coordinator.installMouseMonitor()
        context.coordinator.updateHeight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // During IME composition the marked text lives in NSTextView before
        // it is committed to the SwiftUI binding. Writing the older binding
        // value back here destroys the first composing character while the
        // input method still owns its candidate session.
        if !textView.hasMarkedText(), textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
        }
        context.coordinator.updateHeight()
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeMouseMonitor()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        weak var textView: NSTextView?
        private var mouseMonitor: Any?

        init(parent: NativeTextEditor) { self.parent = parent }

        func installMouseMonitor() {
            guard mouseMonitor == nil else { return }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                guard let self,
                      let textView = self.textView,
                      let window = textView.window,
                      event.window === window,
                      window.firstResponder === textView else { return event }
                let point = textView.convert(event.locationInWindow, from: nil)
                if !textView.bounds.contains(point) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }

        func removeMouseMonitor() {
            guard let mouseMonitor else { return }
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }

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

private final class NativeComposerTextView: NSTextView {
    var compositionChanged: ((Bool) -> Void)?

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        compositionChanged?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        compositionChanged?(false)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        compositionChanged?(hasMarkedText())
    }
}
