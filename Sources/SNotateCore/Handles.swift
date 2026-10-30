import CoreGraphics
import Foundation

/// A grab point on a selected annotation (SN-208).
public enum Handle: Sendable, Hashable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case start
    case end
    /// An arrow's bend; sits at the midpoint while the arrow is straight.
    case curve
    case leader
}

/// Handles, resizing and moving in stored image pixels. Modifiers follow
/// SN-503: `constrain` (shift) keeps a rectangle's aspect on corner handles
/// and snaps an arrow end to 45 degrees; `fromCentre` (option) resizes
/// about the centre. Dragging past the opposite side flips the rectangle.
extension Geometry {
    static let rectHandles: [Handle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]

    public static func handles(of shape: Shape) -> [(handle: Handle, point: CGPoint)] {
        switch shape {
        case .rectangle(let rect, _), .ellipse(let rect, _), .highlight(let rect, _), .blur(let rect, _):
            return handles(of: rect)
        case .arrow(let from, let to, let curve):
            let bend = curve ?? CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            return [(.start, from), (.end, to), (.curve, bend)]
        case .text(_, _, _, let leader?):
            return [(.leader, leader)]
        case .text, .counter, .unknown:
            return []
        }
    }

    /// The eight handles of a rectangle, also used for the crop.
    public static func handles(of rect: CGRect) -> [(handle: Handle, point: CGPoint)] {
        rectHandles.map { ($0, point(of: $0, in: rect)) }
    }

    public static func dragging(
        _ shape: Shape,
        handle: Handle,
        to point: CGPoint,
        constrain: Bool,
        fromCentre: Bool
    ) -> Shape {
        func resize(_ rect: CGRect) -> CGRect {
            resized(rect, handle: handle, to: point, constrain: constrain, fromCentre: fromCentre)
        }
        let isRectHandle = rectHandles.contains(handle)
        switch shape {
        case .rectangle(let rect, let fill) where isRectHandle:
            return .rectangle(resize(rect), fill: fill)
        case .ellipse(let rect, let fill) where isRectHandle:
            return .ellipse(resize(rect), fill: fill)
        case .highlight(let rect, let spotlight) where isRectHandle:
            return .highlight(resize(rect), spotlight: spotlight)
        case .blur(let rect, let pixelate) where isRectHandle:
            return .blur(resize(rect), pixelate: pixelate)
        case .arrow(let from, let to, let curve):
            switch handle {
            case .start:
                return .arrow(from: constrain ? snapped45(point, about: to) : point, to: to, curve: curve)
            case .end:
                return .arrow(from: from, to: constrain ? snapped45(point, about: from) : point, curve: curve)
            case .curve:
                return .arrow(from: from, to: to, curve: point)
            default:
                return shape
            }
        case .text(let at, let text, let pill, .some) where handle == .leader:
            return .text(at: at, text: text, pill: pill, leader: point)
        default:
            return shape
        }
    }

    public static func resized(
        _ rect: CGRect,
        handle: Handle,
        to point: CGPoint,
        constrain: Bool,
        fromCentre: Bool
    ) -> CGRect {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        switch handle {
        case .top, .bottom:
            if fromCentre {
                let half = abs(point.y - centre.y)
                return CGRect(x: rect.minX, y: centre.y - half, width: rect.width, height: 2 * half)
            }
            let fixed = handle == .top ? rect.maxY : rect.minY
            return CGRect(x: rect.minX, y: min(fixed, point.y), width: rect.width, height: abs(fixed - point.y))
        case .left, .right:
            if fromCentre {
                let half = abs(point.x - centre.x)
                return CGRect(x: centre.x - half, y: rect.minY, width: 2 * half, height: rect.height)
            }
            let fixed = handle == .left ? rect.maxX : rect.minX
            return CGRect(x: min(fixed, point.x), y: rect.minY, width: abs(fixed - point.x), height: rect.height)
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            let anchor = fromCentre ? centre : Self.point(of: opposite(handle), in: rect)
            var dx = point.x - anchor.x
            var dy = point.y - anchor.y
            if constrain {
                let aspect = rect.width > 0 && rect.height > 0 ? rect.width / rect.height : 1
                if abs(dx) / aspect >= abs(dy) {
                    dy = (dy < 0 ? -1 : 1) * abs(dx) / aspect
                } else {
                    dx = (dx < 0 ? -1 : 1) * abs(dy) * aspect
                }
            }
            if fromCentre {
                return CGRect(x: anchor.x - abs(dx), y: anchor.y - abs(dy), width: 2 * abs(dx), height: 2 * abs(dy))
            }
            return CGRect(x: anchor.x, y: anchor.y, width: dx, height: dy).standardized
        default:
            return rect
        }
    }

    public static func moved(_ shape: Shape, by offset: CGVector) -> Shape {
        func move(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
        }
        func move(_ rect: CGRect) -> CGRect {
            rect.offsetBy(dx: offset.dx, dy: offset.dy)
        }
        switch shape {
        case .arrow(let from, let to, let curve):
            return .arrow(from: move(from), to: move(to), curve: curve.map(move))
        case .rectangle(let rect, let fill):
            return .rectangle(move(rect), fill: fill)
        case .ellipse(let rect, let fill):
            return .ellipse(move(rect), fill: fill)
        case .counter(let at):
            return .counter(at: move(at))
        case .text(let at, let text, let pill, let leader):
            return .text(at: move(at), text: text, pill: pill, leader: leader.map(move))
        case .highlight(let rect, let spotlight):
            return .highlight(move(rect), spotlight: spotlight)
        case .blur(let rect, let pixelate):
            return .blur(move(rect), pixelate: pixelate)
        case .unknown:
            return shape
        }
    }

    /// The crop limited to the image (SN-207), `nil` when nothing is left.
    public static func clampedCrop(_ rect: CGRect, to size: PixelSize) -> CGRect? {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return clamped.isNull || clamped.isEmpty ? nil : clamped
    }

    /// The largest rectangle of `aspect` (width over height) centred in
    /// `rect`, for the crop's aspect lock.
    public static func fitted(_ rect: CGRect, aspect: CGFloat) -> CGRect {
        guard aspect > 0, rect.height > 0 else {
            return rect
        }
        if rect.width / rect.height > aspect {
            let width = rect.height * aspect
            return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        }
        let height = rect.width / aspect
        return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
    }

    static func point(of handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        default:
            return CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    static func opposite(_ handle: Handle) -> Handle {
        switch handle {
        case .topLeft:
            return .bottomRight
        case .topRight:
            return .bottomLeft
        case .bottomRight:
            return .topLeft
        case .bottomLeft:
            return .topRight
        case .top:
            return .bottom
        case .bottom:
            return .top
        case .left:
            return .right
        case .right:
            return .left
        default:
            return handle
        }
    }

    /// `point` turned about `centre` to the nearest multiple of 45 degrees,
    /// keeping its distance.
    static func snapped45(_ point: CGPoint, about centre: CGPoint) -> CGPoint {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let length = hypot(dx, dy)
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: centre.x + length * cos(angle), y: centre.y + length * sin(angle))
    }
}
