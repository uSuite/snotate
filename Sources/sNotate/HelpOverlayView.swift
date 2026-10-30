import AppKit
import SNotateCore

/// The live keymap over the window (SN-503), in the sections docs/keys.md
/// has: `?`, `esc` or a click closes it. Drawn rather than built from
/// fields, so snapshots show it, in as many columns as the window fits.
final class HelpOverlayView: NSView {
    var sections: [KeyHelp.Section] = [] {
        didSet {
            needsDisplay = true
        }
    }
    var onClose: (() -> Void)?

    private static let margin: CGFloat = 28
    private static let columnWidth: CGFloat = 250
    private static let gap: CGFloat = 24
    private static let keysWidth: CGFloat = 92
    private static let rowHeight: CGFloat = 16

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.06, alpha: 0.95).setFill()
        bounds.fill()
        let title: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor.white,
        ]
        let hint: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(white: 0.65, alpha: 1),
        ]
        let heading: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.white,
        ]
        let subheading: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(white: 0.65, alpha: 1),
        ]
        let keys: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: Brand.accent,
        ]
        let command: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(white: 0.9, alpha: 1),
        ]
        let margin = Self.margin
        NSAttributedString(string: "sNotate keys", attributes: title).draw(at: CGPoint(x: margin, y: margin - 8))
        NSAttributedString(string: "? or esc to close; ~/.config/snotate/keymap changes them", attributes: hint)
            .draw(at: CGPoint(x: margin + 112, y: margin - 5))
        let top = margin + 26
        var x = margin
        var y = top
        for section in sections {
            let height = (section.isMain ? 24 : 20) + CGFloat(section.rows.count) * Self.rowHeight
            // A section starts a new column when it would not fit, unless the
            // column is empty and the section taller than the window.
            if y + height > bounds.height - margin, y > top {
                x += Self.columnWidth + Self.gap
                y = top
            }
            if section.isMain {
                y += y > top ? 6 : 0
                NSAttributedString(string: section.title, attributes: heading).draw(at: CGPoint(x: x, y: y))
                y += 18
            } else {
                NSAttributedString(string: section.title, attributes: subheading).draw(at: CGPoint(x: x, y: y + 2))
                y += 18
            }
            for row in section.rows {
                NSAttributedString(string: row.keys, attributes: keys).draw(at: CGPoint(x: x, y: y))
                NSAttributedString(string: row.command, attributes: command)
                    .draw(in: CGRect(x: x + Self.keysWidth, y: y, width: Self.columnWidth - Self.keysWidth, height: Self.rowHeight))
                y += Self.rowHeight
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "?" || event.keyCode == 53 {
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClose?()
    }
}
