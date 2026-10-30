import CoreGraphics
import Foundation

/// Points are `[x, y]` and rectangles `[x, y, width, height]`, in image
/// pixels with the origin top-left and y down. Rectangles are normalised to a
/// non-negative size on read.
extension Sidecar {
    static func point(_ value: JSONValue, _ path: String) throws(SidecarError) -> CGPoint {
        guard let numbers = numbers(value, count: 2) else {
            throw .wrongType(key: path, expected: "[x, y]")
        }
        return CGPoint(x: numbers[0], y: numbers[1])
    }

    static func rect(_ value: JSONValue, _ path: String) throws(SidecarError) -> CGRect {
        guard let numbers = numbers(value, count: 4) else {
            throw .wrongType(key: path, expected: "[x, y, width, height]")
        }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]).standardized
    }

    static func json(_ point: CGPoint) -> JSONValue {
        .array([.number(Double(point.x)), .number(Double(point.y))])
    }

    static func json(_ rect: CGRect) -> JSONValue {
        .array([
            .number(Double(rect.minX)),
            .number(Double(rect.minY)),
            .number(Double(rect.width)),
            .number(Double(rect.height)),
        ])
    }

    private static func numbers(_ value: JSONValue, count: Int) -> [Double]? {
        guard case .array(let array) = value, array.count == count else {
            return nil
        }
        var result: [Double] = []
        for element in array {
            guard case .number(let number) = element, number.isFinite else {
                return nil
            }
            result.append(number)
        }
        return result
    }
}

/// The precision the sidecar keeps (two decimals, as `SidecarWriter`
/// rounds), applied to every edit so the document in memory is exactly what
/// reading the file back gives; otherwise our own save would look like an
/// outside change and reload away the selection and undo.
enum StoredPrecision {
    static func round(_ value: CGFloat) -> CGFloat {
        (value * 100).rounded() / 100 + 0
    }

    static func round(_ point: CGPoint) -> CGPoint {
        CGPoint(x: round(point.x), y: round(point.y))
    }

    static func round(_ rect: CGRect) -> CGRect {
        CGRect(x: round(rect.minX), y: round(rect.minY), width: round(rect.width), height: round(rect.height))
    }

    static func round(_ shape: Shape) -> Shape {
        switch shape {
        case .arrow(let from, let to, let curve):
            return .arrow(from: round(from), to: round(to), curve: curve.map(round))
        case .rectangle(let rect, let fill):
            return .rectangle(round(rect), fill: fill)
        case .ellipse(let rect, let fill):
            return .ellipse(round(rect), fill: fill)
        case .counter(let at):
            return .counter(at: round(at))
        case .text(let at, let text, let pill, let leader):
            return .text(at: round(at), text: text, pill: pill, leader: leader.map(round))
        case .highlight(let rect, let spotlight):
            return .highlight(round(rect), spotlight: spotlight)
        case .blur(let rect, let pixelate):
            return .blur(round(rect), pixelate: pixelate)
        case .unknown:
            return shape
        }
    }
}

/// Stored annotation coordinates to the pixels of the image on disk: scaled
/// by the step's whole-multiple factor, unscaled when sizes match, are
/// unknown or are flagged (DECISIONS 2026-10-26). Edits made on a scaled step
/// go back through `toStored`, so the sidecar keeps its recorded size.
public struct StepTransform: Sendable, Equatable {
    public let factor: CGFloat

    public init(scale: StepScale?) {
        if case .scaled(let factor) = scale {
            self.factor = CGFloat(factor)
        } else {
            factor = 1
        }
    }

    public func toImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * factor, y: point.y * factor)
    }

    public func toStored(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / factor, y: point.y / factor)
    }

    public func toImage(_ rect: CGRect) -> CGRect {
        CGRect(origin: toImage(rect.origin), size: CGSize(width: rect.width * factor, height: rect.height * factor))
    }

    public func toStored(_ rect: CGRect) -> CGRect {
        CGRect(origin: toStored(rect.origin), size: CGSize(width: rect.width / factor, height: rect.height / factor))
    }
}

/// Image pixels to view points and back: a scale and an offset, both chosen
/// by the canvas through its `Viewport`.
public struct ViewTransform: Sendable, Equatable {
    /// View points per image pixel.
    public var scale: CGFloat
    /// Where image pixel (0, 0) lands in the view.
    public var offset: CGPoint

    public init(scale: CGFloat, offset: CGPoint = .zero) {
        self.scale = scale
        self.offset = offset
    }

    public func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
    }

    public func toImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
    }

    public func toView(_ rect: CGRect) -> CGRect {
        CGRect(origin: toView(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }

    public func toImage(_ rect: CGRect) -> CGRect {
        CGRect(origin: toImage(rect.origin), size: CGSize(width: rect.width / scale, height: rect.height / scale))
    }

    /// A length in view points, such as a hit tolerance, in image pixels.
    public func toImage(length: CGFloat) -> CGFloat {
        length / scale
    }
}
