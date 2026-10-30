import CoreGraphics

/// Hit-testing (SN-208). Points and the tolerance are in stored image
/// pixels; the canvas converts a few view points of slop with
/// `ViewTransform.toImage(length:)`. Lines and unfilled outlines are hit
/// near the stroke, everything else inside.
extension Geometry {
    public static func hits(
        _ shape: Shape,
        _ point: CGPoint,
        style: Style,
        tolerance: CGFloat
    ) -> Bool {
        let reach = style.strokeWidth / 2 + tolerance
        switch shape {
        case .arrow(let from, let to, nil):
            return distance(point, toSegment: from, to) <= reach
        case .arrow(let from, let to, let curve?):
            return distance(point, toPolyline: quadratic(from, curve, to)) <= reach
        case .rectangle(let rect, false):
            return distance(point, toBorderOf: rect) <= reach
        case .rectangle(let rect, true):
            return rect.insetBy(dx: -reach, dy: -reach).contains(point)
        case .ellipse(let rect, let fill):
            return distance(point, toEllipse: rect, inside: fill) <= reach
        case .counter(let at):
            return hypot(point.x - at.x, point.y - at.y) <= style.counterRadius + tolerance
        case .text, .highlight, .blur:
            return bounds(of: shape, style: style).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .unknown:
            return false
        }
    }

    /// The last annotation in drawing order under `point`.
    public static func topmost(
        at point: CGPoint,
        in items: [Annotation],
        styles: Styles,
        tolerance: CGFloat
    ) -> Annotation.ID? {
        items.last { item in
            hits(item.shape, point, style: styles.style(for: item.preset), tolerance: tolerance)
        }?.id
    }

    /// Annotations whose bounds intersect `rect`, in drawing order.
    public static func marquee(
        _ rect: CGRect,
        in items: [Annotation],
        styles: Styles
    ) -> [Annotation.ID] {
        items.filter { item in
            let box = bounds(of: item.shape, style: styles.style(for: item.preset))
            return !box.isNull && box.intersects(rect)
        }.map(\.id)
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    static func distance(_ p: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).map { distance(p, toSegment: $0, $1) }.min() ?? .infinity
    }

    /// A quadratic Bézier as 32 segments, the curve the renderer draws.
    static func quadratic(_ a: CGPoint, _ control: CGPoint, _ b: CGPoint) -> [CGPoint] {
        (0...32).map { step in
            let t = CGFloat(step) / 32
            let u = 1 - t
            return CGPoint(
                x: u * u * a.x + 2 * u * t * control.x + t * t * b.x,
                y: u * u * a.y + 2 * u * t * control.y + t * t * b.y
            )
        }
    }

    static func distance(_ p: CGPoint, toBorderOf rect: CGRect) -> CGFloat {
        if rect.contains(p) {
            return min(p.x - rect.minX, rect.maxX - p.x, p.y - rect.minY, rect.maxY - p.y)
        }
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Distance to the ellipse's outline, or 0 inside it when `inside` counts.
    /// Measured along the ray from the centre, close enough for picking.
    static func distance(_ p: CGPoint, toEllipse rect: CGRect, inside: Bool) -> CGFloat {
        let a = rect.width / 2
        let b = rect.height / 2
        guard a > 0, b > 0 else {
            return distance(p, toBorderOf: rect)
        }
        let dx = p.x - rect.midX
        let dy = p.y - rect.midY
        let k = ((dx / a) * (dx / a) + (dy / b) * (dy / b)).squareRoot()
        if inside, k <= 1 {
            return 0
        }
        guard k > 0 else {
            return min(a, b)
        }
        return abs(1 - 1 / k) * hypot(dx, dy)
    }
}
