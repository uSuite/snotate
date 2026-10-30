import AppKit

/// The caret and selection over text being typed on the canvas. Its own
/// glyphs are transparent: the canvas draws the text through the export
/// renderer, so what is typed looks exactly as it will be exported
/// (DECISIONS 2026-10-27). Enter commits, shift-enter breaks the line, esc
/// commits; its own undo is off so the case has one history.
final class InPlaceTextView: NSTextView {
    var onChange: ((String) -> Void)?
    var onCommit: (() -> Void)?
    private var shiftHeld = false

    init(fontSize: CGFloat, lineHeight: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: 4, height: lineHeight))
        drawsBackground = false
        isRichText = false
        allowsUndo = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
        isHorizontallyResizable = true
        isVerticallyResizable = true
        maxSize = NSSize(width: 100_000, height: 100_000)
        insertionPointColor = Brand.accent
        selectedTextAttributes = [.backgroundColor: Brand.accent.withAlphaComponent(0.3)]
        delegate = self
        setFont(size: fontSize, lineHeight: lineHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    /// The system font at the canvas's scale, with the renderer's line
    /// height so the caret sits on the drawn glyphs.
    func setFont(size: CGFloat, lineHeight: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let font = NSFont.systemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.clear,
            .paragraphStyle: paragraph,
        ]
        typingAttributes = attributes
        defaultParagraphStyle = paragraph
        textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: textStorage?.length ?? 0))
        minSize = NSSize(width: 2, height: lineHeight)
        sizeToFit()
    }

    override func keyDown(with event: NSEvent) {
        shiftHeld = event.modifierFlags.contains(.shift)
        super.keyDown(with: event)
    }
}

extension InPlaceTextView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        sizeToFit()
        onChange?(string)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)) where !shiftHeld,
            #selector(NSResponder.cancelOperation(_:)):
            onCommit?()
            return true
        default:
            return false
        }
    }
}
