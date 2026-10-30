import CoreGraphics
import CoreText
import Foundation

/// Pure geometry on annotations in stored image pixels: bounds now, hit
/// testing, handles and snapping beside it. The renderer draws with the same
/// measurements, so what is hit is what is drawn.
public enum Geometry {
    /// How far an arrow head reaches past the line, either side.
    public static func arrowHeadReach(_ style: Style) -> CGFloat {
        style.strokeWidth * 3
    }

    /// Padding around text drawn on a pill.
    public static func pillPadding(_ style: Style) -> CGFloat {
        style.fontSize * 0.3
    }

    public static func bounds(of shape: Shape, style: Style) -> CGRect {
        let half = style.strokeWidth / 2
        switch shape {
        case .arrow(let from, let to, let curve):
            let reach = arrowHeadReach(style)
            return enclosing([from, to] + (curve.map { [$0] } ?? []))
                .insetBy(dx: -reach, dy: -reach)
        case .rectangle(let rect, _), .ellipse(let rect, _):
            return rect.insetBy(dx: -half, dy: -half)
        case .counter(let at):
            let r = style.counterRadius
            return CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r)
        case .text(let at, let text, let pill, let leader):
            var box = CGRect(origin: at, size: TextLayout(text: text, fontSize: style.fontSize).size)
            if pill {
                let padding = pillPadding(style)
                box = box.insetBy(dx: -padding, dy: -padding)
            }
            if let leader {
                box = box.union(CGRect(origin: leader, size: .zero).insetBy(dx: -half, dy: -half))
            }
            return box
        case .highlight(let rect, _), .blur(let rect, _):
            return rect
        case .unknown:
            return .null
        }
    }

    /// The shape's own geometry without stroke: the rectangle of a
    /// rectangle-like shape, the points of an arrow. A dragged point snaps
    /// to these, so a corner drawn onto another rectangle's corner meets it
    /// exactly; a moved shape snaps by its bounds, outer edge to outer edge.
    public static func outline(of shape: Shape, style: Style) -> CGRect {
        switch shape {
        case .arrow(let from, let to, let curve):
            return enclosing([from, to] + (curve.map { [$0] } ?? []))
        case .rectangle(let rect, _), .ellipse(let rect, _), .highlight(let rect, _), .blur(let rect, _):
            return rect
        case .counter, .text, .unknown:
            return bounds(of: shape, style: style)
        }
    }

    static func enclosing(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(
            x: xs.min()!,
            y: ys.min()!,
            width: xs.max()! - xs.min()!,
            height: ys.max()! - ys.min()!
        )
    }
}

/// Text set in the system font, one line per `\n`, measured the way the
/// renderer will draw it.
public struct TextLayout: Sendable {
    public let lines: [String]
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    /// Distance from a line's top to its baseline.
    public let ascent: CGFloat
    public let size: CGSize

    /// The system font, or its bold face for counter numbers.
    static func font(size: CGFloat, bold: Bool = false) -> CTFont {
        CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func line(_ text: String, font: CTFont, color: CGColor? = nil) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    public init(text: String, fontSize: CGFloat) {
        let font = Self.font(size: fontSize)
        lines = text.components(separatedBy: "\n")
        self.fontSize = fontSize
        ascent = CTFontGetAscent(font)
        lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        let width = lines.map { line -> CGFloat in
            CGFloat(CTLineGetTypographicBounds(Self.line(line, font: font), nil, nil, nil))
        }.max() ?? 0
        size = CGSize(width: ceil(width), height: ceil(lineHeight * CGFloat(lines.count)))
    }
}
