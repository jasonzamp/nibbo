import AppKit
import SwiftUI

/// Plain-text script editor that reports which line was clicked
/// and highlights the line the prompter is currently on.
struct ScriptEditor: NSViewRepresentable {
    @Binding var text: String
    var highlightedLine: Int?
    var followHighlight: Bool
    var onClickLine: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ClickTextView(usingTextLayoutManager: false) // TextKit 1 for temporary attributes
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.delegate = context.coordinator
        textView.onClick = { [weak coordinator = context.coordinator] location in
            coordinator?.clicked(at: location)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            coordinator.shownLine = nil
        }
        coordinator.highlight(highlightedLine, in: textView, follow: followHighlight)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptEditor
        var shownLine: Int?
        private var shownText = ""
        private weak var textView: NSTextView?

        init(_ parent: ScriptEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func clicked(at location: Int) {
            guard let textView else { return }
            let ns = textView.string as NSString
            let line = ns.substring(to: min(location, ns.length)).components(separatedBy: "\n").count - 1
            parent.onClickLine(line)
        }

        func highlight(_ line: Int?, in textView: NSTextView, follow: Bool) {
            self.textView = textView
            guard line != shownLine || textView.string != shownText,
                  let layoutManager = textView.layoutManager else { return }
            let lineChanged = line != shownLine
            shownLine = line
            shownText = textView.string

            let ns = textView.string as NSString
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: ns.length))
            guard let line, let range = Self.range(ofLine: line, in: ns), range.length > 0 else { return }
            layoutManager.addTemporaryAttribute(.backgroundColor,
                                                value: NSColor.controlAccentColor.withAlphaComponent(0.22),
                                                forCharacterRange: range)
            if follow && lineChanged { textView.scrollRangeToVisible(range) }
        }

        private static func range(ofLine line: Int, in ns: NSString) -> NSRange? {
            var location = 0
            for (i, text) in (ns as String).components(separatedBy: "\n").enumerated() {
                let length = (text as NSString).length
                if i == line { return NSRange(location: location, length: length) }
                location += length + 1
            }
            return nil
        }
    }
}

/// Reports a plain click (not a drag-selection) once the mouse is released.
final class ClickTextView: NSTextView {
    var onClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event) // runs the selection tracking loop until mouse-up
        let selection = selectedRange()
        if selection.length == 0 { onClick?(selection.location) }
    }
}
