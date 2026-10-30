import AppKit
import SNotateCore

/// Zoom and pan (SN-502): the Dispatcher's view effects, pinch and scroll,
/// all applied through the `Viewport` so keys and gestures share one path.
extension CanvasView {
    /// One pan key moves an eighth of the view, a shifted one most of it.
    static let panShare: CGFloat = 1 / 8
    static let bigPanShare: CGFloat = 0.9

    func zoom(_ request: ZoomRequest) {
        guard let frame = viewportFrame else {
            return
        }
        switch request {
        case .steps(let n):
            viewport.zoom(by: pow(Viewport.step, CGFloat(n)), in: frame)
        case .fit:
            viewport.fit()
        case .actual:
            viewport.actual(in: frame)
        case .area(let rect):
            viewport.show(rect, in: frame)
        case .inAt(let point):
            viewport.zoom(by: Viewport.step, at: viewPoint(point), in: frame)
        }
        viewChanged()
        editor?.onMessage?("\(Int((viewport.ratio(in: frame) * 100).rounded()))%")
    }

    /// Arrow keys with nothing selected: only along an axis that overflows.
    func pan(_ direction: Command.Direction, big: Bool) {
        guard let frame = viewportFrame else {
            return
        }
        let share = big ? Self.bigPanShare : Self.panShare
        let overflows = viewport.overflows(in: frame)
        let dx = share * bounds.width
        let dy = share * bounds.height
        switch direction {
        case .left where overflows.horizontally:
            pan(by: CGVector(dx: dx, dy: 0))
        case .right where overflows.horizontally:
            pan(by: CGVector(dx: -dx, dy: 0))
        case .up where overflows.vertically:
            pan(by: CGVector(dx: 0, dy: dy))
        case .down where overflows.vertically:
            pan(by: CGVector(dx: 0, dy: -dy))
        default:
            break
        }
    }

    /// Moves the content by `delta` view points, as a hand drags it.
    func pan(by delta: CGVector) {
        guard let frame = viewportFrame else {
            return
        }
        viewport.pan(by: delta, in: frame)
        viewChanged()
    }

    override func magnify(with event: NSEvent) {
        guard let frame = viewportFrame else {
            return
        }
        viewport.zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil), in: frame)
        viewChanged()
    }

    /// Two-finger scroll pans; cmd-scroll and a mouse wheel's notches with
    /// cmd zoom about the pointer.
    override func scrollWheel(with event: NSEvent) {
        guard let frame = viewportFrame else {
            return
        }
        let precise = event.hasPreciseScrollingDeltas
        if event.modifierFlags.contains(.command) {
            let notches = precise ? event.scrollingDeltaY / 40 : event.scrollingDeltaY
            viewport.zoom(by: pow(Viewport.step, notches), at: convert(event.locationInWindow, from: nil), in: frame)
            viewChanged()
            return
        }
        let lines: CGFloat = precise ? 1 : 16
        pan(by: CGVector(dx: event.scrollingDeltaX * lines, dy: event.scrollingDeltaY * lines))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        captureView.frame = frame
        placeField()
    }

    private func viewChanged() {
        placeField()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
}
