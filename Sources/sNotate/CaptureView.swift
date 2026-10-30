import AppKit
import QuartzCore
import SNotateCore

/// The capture under the canvas (SN-606), as the contents of a layer the
/// GPU scales: drawn by the canvas, it was replayed on the main thread
/// through a half-float pass every frame, most of a frame at 120 Hz. The
/// canvas draws every annotation and overlay over it with the one renderer.
/// Snapshots, which do not composite layers, get it from `draw(_:)`.
final class CaptureView: NSView {
    private let imageLayer = CALayer()
    private var image: CGImage?
    private var rect: CGRect = .zero
    private var nearest = false

    // Not flipped: in a flipped view's layer, image contents of a sublayer
    // show upside down. `show` takes the canvas's flipped points.
    override var wantsUpdateLayer: Bool { true }

    /// `image` filling `rect` in the canvas's flipped view points;
    /// `nearest` shows the pixels when zoomed far in.
    func show(
        _ image: CGImage?,
        in rect: CGRect,
        nearest: Bool
    ) {
        guard image !== self.image || rect != self.rect || nearest != self.nearest else {
            return
        }
        let unflipped = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        self.image = image
        self.rect = rect
        self.nearest = nearest
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        imageLayer.frame = unflipped
        imageLayer.magnificationFilter = nearest ? .nearest : .linear
        imageLayer.minificationFilter = .linear
        CATransaction.commit()
    }

    override func updateLayer() {
        layer?.backgroundColor = Brand.canvas.cgColor
        if imageLayer.superlayer == nil {
            layer?.addSublayer(imageLayer)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Brand.canvas.setFill()
        bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        context.interpolationQuality = nearest ? .none : .high
        context.draw(image, in: CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height))
    }
}
