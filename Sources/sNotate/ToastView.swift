import AppKit

/// A short message at the bottom of the canvas that fades by itself: why an
/// edit was refused, or that a reload dropped a change.
final class ToastView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hide: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.75).cgColor
        layer?.cornerRadius = 8
        label.textColor = .white
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func show(_ text: String, in parent: NSView) {
        label.stringValue = text
        label.sizeToFit()
        let width = min(label.frame.width + 24, parent.bounds.width - 32)
        let height = label.frame.height + 14
        // 16 points above the bottom edge whether or not the parent is flipped.
        let y = parent.isFlipped ? parent.bounds.height - height - 16 : 16
        frame = NSRect(x: (parent.bounds.width - width) / 2, y: y, width: width, height: height)
        label.frame = bounds.insetBy(dx: 12, dy: 7)
        autoresizingMask = [.minXMargin, .maxXMargin, parent.isFlipped ? .minYMargin : .maxYMargin]
        if superview !== parent {
            parent.addSubview(self)
        }
        alphaValue = 1
        hide?.cancel()
        hide = MainQueue.after(3) { [weak self] in
            NSAnimationContext.runAnimationGroup(
                { _ in
                    self?.animator().alphaValue = 0
                },
                completionHandler: nil
            )
        }
    }
}
