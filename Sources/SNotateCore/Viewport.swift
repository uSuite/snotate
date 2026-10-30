import CoreGraphics

/// Zoom and pan of the canvas (SN-502), kept out of the view so it is unit
/// tested; modelled on sView's `CanvasGeometry`, without rotation.
///
/// Zoom is device pixels per image pixel, as in sView: fit is never above
/// 1, so captures stay sharp, and actual size is 1:1 on a Retina screen.
/// Both the zoom and the centre are held in stored pixels, so a re-shot 2x
/// step shows the same region as the 1x steps around it (DECISIONS
/// 2026-10-27). Zoom is view state: never in the sidecar or the undo.
public struct Viewport: Sendable, Equatable {
    public enum Zoom: Sendable, Equatable {
        case fit
        /// Device pixels per stored pixel.
        case scale(CGFloat)
    }

    /// The current step's image and the view showing it.
    public struct Frame: Sendable, Equatable {
        /// Image pixels.
        public var imageSize: CGSize
        /// The step's whole-multiple factor, image pixels per stored pixel.
        public var factor: CGFloat
        /// View points.
        public var viewSize: CGSize
        public var backingScale: CGFloat

        public init(
            imageSize: CGSize,
            factor: CGFloat = 1,
            viewSize: CGSize,
            backingScale: CGFloat = 2
        ) {
            self.imageSize = imageSize
            self.factor = factor
            self.viewSize = viewSize
            self.backingScale = backingScale
        }

        var storedSize: CGSize {
            CGSize(width: imageSize.width / factor, height: imageSize.height / factor)
        }

        var viewCentre: CGPoint {
            CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        }

        var isEmpty: Bool {
            imageSize.width <= 0 || imageSize.height <= 0 || viewSize.width <= 0 || viewSize.height <= 0
        }
    }

    /// Each zoom key multiplies or divides the scale by this.
    public static let step: CGFloat = 1.25
    /// The largest zoom, in device pixels per image pixel; the smallest is
    /// fit or 0.1, whichever is less.
    public static let maximum: CGFloat = 16

    public var zoom = Zoom.fit
    /// The stored pixel at the view's centre, `nil` for the image's centre.
    public var centre: CGPoint?

    public init(
        zoom: Zoom = .fit,
        centre: CGPoint? = nil
    ) {
        self.zoom = zoom
        self.centre = centre
    }

    /// Device pixels per stored pixel that fit the whole image.
    public static func fitScale(_ frame: Frame) -> CGFloat {
        guard !frame.isEmpty else {
            return 1
        }
        let stored = frame.storedSize
        return min(
            frame.viewSize.width * frame.backingScale / stored.width,
            frame.viewSize.height * frame.backingScale / stored.height,
            frame.factor
        )
    }

    /// Device pixels per stored pixel now.
    public func scale(in frame: Frame) -> CGFloat {
        switch zoom {
        case .fit:
            return Self.fitScale(frame)
        case .scale(let scale):
            return scale
        }
    }

    /// The zoom as a share of actual size, 1 meaning 100%.
    public func ratio(in frame: Frame) -> CGFloat {
        scale(in: frame) / frame.factor
    }

    public func overflows(in frame: Frame) -> (horizontally: Bool, vertically: Bool) {
        let points = scale(in: frame) / frame.backingScale
        let stored = frame.storedSize
        return (stored.width * points > frame.viewSize.width + 0.5, stored.height * points > frame.viewSize.height + 0.5)
    }

    /// Image pixels to view points: the image covers the view on axes where
    /// it overflows and is centred on the others, on whole device pixels.
    public func transform(in frame: Frame) -> ViewTransform {
        let scale = scale(in: frame)
        let centre = clamped(centre, scale: scale, in: frame)
        let points = scale / frame.backingScale
        let view = frame.viewCentre
        func device(_ value: CGFloat) -> CGFloat {
            (value * frame.backingScale).rounded() / frame.backingScale
        }
        return ViewTransform(
            scale: points / frame.factor,
            offset: CGPoint(x: device(view.x - centre.x * points), y: device(view.y - centre.y * points))
        )
    }

    /// Multiplies the zoom by `factor`, keeping the stored point under
    /// `anchor` (view points) where it is.
    public mutating func zoom(
        by factor: CGFloat,
        at anchor: CGPoint? = nil,
        in frame: Frame
    ) {
        set(scale: scale(in: frame) * factor, at: anchor, in: frame)
    }

    /// Actual size, one device pixel per image pixel, about the centre.
    public mutating func actual(in frame: Frame) {
        set(scale: frame.factor, at: nil, in: frame)
    }

    public mutating func fit() {
        zoom = .fit
        centre = nil
    }

    /// Shows `rect` (stored pixels) as large as the view allows.
    public mutating func show(_ rect: CGRect, in frame: Frame) {
        guard !frame.isEmpty, rect.width > 0, rect.height > 0 else {
            return
        }
        let scale = min(
            frame.viewSize.width * frame.backingScale / rect.width,
            frame.viewSize.height * frame.backingScale / rect.height
        )
        zoom = .scale(Self.limited(scale, in: frame))
        centre = clamped(CGPoint(x: rect.midX, y: rect.midY), scale: self.scale(in: frame), in: frame)
    }

    /// Moves the image by `delta` view points, the way the content follows
    /// a hand: a positive dx shows what is to the left.
    public mutating func pan(by delta: CGVector, in frame: Frame) {
        guard case .scale(let scale) = zoom else {
            return
        }
        let points = scale / frame.backingScale
        let now = clamped(centre, scale: scale, in: frame)
        centre = clamped(CGPoint(x: now.x - delta.dx / points, y: now.y - delta.dy / points), scale: scale, in: frame)
    }

    private mutating func set(
        scale: CGFloat,
        at anchor: CGPoint?,
        in frame: Frame
    ) {
        guard !frame.isEmpty else {
            return
        }
        let anchor = anchor ?? frame.viewCentre
        let transform = transform(in: frame)
        let fixed = transform.toImage(anchor)
        let stored = CGPoint(x: fixed.x / frame.factor, y: fixed.y / frame.factor)
        let new = Self.limited(scale, in: frame)
        let points = new / frame.backingScale
        let view = frame.viewCentre
        zoom = .scale(new)
        centre = clamped(
            CGPoint(x: stored.x - (anchor.x - view.x) / points, y: stored.y - (anchor.y - view.y) / points),
            scale: new,
            in: frame
        )
    }

    private static func limited(_ scale: CGFloat, in frame: Frame) -> CGFloat {
        let lowest = min(fitScale(frame), 0.1 * frame.factor)
        return min(max(scale, lowest), maximum * frame.factor)
    }

    /// The centre that keeps the image covering the view on an axis where
    /// it overflows, and the image's centre on an axis where it does not.
    private func clamped(
        _ centre: CGPoint?,
        scale: CGFloat,
        in frame: Frame
    ) -> CGPoint {
        let stored = frame.storedSize
        let middle = CGPoint(x: stored.width / 2, y: stored.height / 2)
        guard let centre, !frame.isEmpty else {
            return middle
        }
        let points = scale / frame.backingScale
        func axis(_ value: CGFloat, length: CGFloat, view: CGFloat) -> CGFloat {
            let half = view / 2 / points
            guard length > 2 * half else {
                return length / 2
            }
            return min(max(value, half), length - half)
        }
        return CGPoint(
            x: axis(centre.x, length: stored.width, view: frame.viewSize.width),
            y: axis(centre.y, length: stored.height, view: frame.viewSize.height)
        )
    }
}
