import CoreGraphics
import Foundation

/// Snapping while drawing and dragging (SN-209), in stored image pixels.
/// A value within `threshold` of an image edge or centre, or of another
/// object's edge or centre, snaps to the closest one and reports a guide to
/// draw; failing that it snaps to the grid, without a guide. Turning it off
/// (`cmd-;`) is the caller not asking.
public struct Snapper: Sendable {
    public enum Axis: Sendable, Hashable {
        /// A vertical guide at an x position.
        case x
        /// A horizontal guide at a y position.
        case y
    }

    public struct Guide: Sendable, Hashable {
        public let axis: Axis
        public let position: CGFloat

        public init(axis: Axis, position: CGFloat) {
            self.axis = axis
            self.position = position
        }
    }

    public var imageSize: PixelSize
    public var targets: [CGRect]
    public var grid: CGFloat?
    public var threshold: CGFloat

    public init(
        imageSize: PixelSize,
        targets: [CGRect] = [],
        grid: CGFloat? = nil,
        threshold: CGFloat = 6
    ) {
        self.imageSize = imageSize
        self.targets = targets
        self.grid = grid
        self.threshold = threshold
    }

    /// Bounds of the annotations a drag can snap to: all but the ones being
    /// moved, and none that are not drawn. With `outlines`, their geometry
    /// without stroke, for snapping a single point.
    public static func targets(
        in items: [Annotation],
        excluding moving: Set<Annotation.ID>,
        styles: Styles,
        outlines: Bool = false
    ) -> [CGRect] {
        items.filter { !moving.contains($0.id) }.compactMap { item in
            let style = styles.style(for: item.preset)
            let bounds = outlines ? Geometry.outline(of: item.shape, style: style) : Geometry.bounds(of: item.shape, style: style)
            return bounds.isNull ? nil : bounds
        }
    }

    public func snap(_ point: CGPoint) -> (point: CGPoint, guides: [Guide]) {
        let x = snap(values: [point.x], axis: .x)
        let y = snap(values: [point.y], axis: .y)
        return (
            CGPoint(x: point.x + x.delta, y: point.y + y.delta),
            (x.guide.map { [$0] } ?? []) + (y.guide.map { [$0] } ?? [])
        )
    }

    /// A rectangle being moved snaps by whichever of its edges or centre is
    /// closest to a candidate, per axis; on the grid its origin snaps.
    public func snap(_ rect: CGRect) -> (rect: CGRect, guides: [Guide]) {
        let x = snap(values: [rect.minX, rect.midX, rect.maxX], axis: .x)
        let y = snap(values: [rect.minY, rect.midY, rect.maxY], axis: .y)
        return (
            rect.offsetBy(dx: x.delta, dy: y.delta),
            (x.guide.map { [$0] } ?? []) + (y.guide.map { [$0] } ?? [])
        )
    }

    private func candidates(_ axis: Axis) -> [CGFloat] {
        let extent = CGFloat(axis == .x ? imageSize.width : imageSize.height)
        var result: [CGFloat] = [0, extent / 2, extent]
        for target in targets {
            result += axis == .x
                ? [target.minX, target.midX, target.maxX]
                : [target.minY, target.midY, target.maxY]
        }
        return result
    }

    private func snap(values: [CGFloat], axis: Axis) -> (delta: CGFloat, guide: Guide?) {
        var best: (delta: CGFloat, position: CGFloat)?
        for value in values {
            for candidate in candidates(axis) {
                let delta = candidate - value
                if abs(delta) <= threshold, abs(delta) < abs(best?.delta ?? .infinity) {
                    best = (delta, candidate)
                }
            }
        }
        if let best {
            return (best.delta, Guide(axis: axis, position: best.position))
        }
        if let grid, grid > 0, let value = values.first {
            let delta = (value / grid).rounded() * grid - value
            if abs(delta) <= threshold {
                return (delta, nil)
            }
        }
        return (0, nil)
    }
}
