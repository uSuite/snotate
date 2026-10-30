import AppKit
import SNotateCore

/// The current step on screen: the cached base (capture and redactions)
/// and the annotations drawn by the same Renderer as export, then the
/// selection, handles, marquee and snapping guides in view space at a fixed
/// size. Flipped, so view points run top-down like image pixels. The image
/// is placed by the `Viewport`: fitted by default and never above one image
/// pixel per device pixel when fitted, zoomed and panned by keys, pinch,
/// scroll and space-drag (SN-502).
final class CanvasView: NSView {
    var editor: CaseEditor? {
        didSet {
            needsDisplay = true
        }
    }

    /// The drag in progress; its preview replaces the step's items.
    var gesture: Gesture? {
        didSet {
            needsDisplay = true
        }
    }

    /// Text being typed in place, and the field showing its caret.
    var textEdit: TextEdit? {
        didSet {
            needsDisplay = true
        }
    }
    var textField: InPlaceTextView?
    var textLayer: StoredPixelLayer?

    /// The window opens a sibling case and the `:` line.
    var onSiblingCase: ((Int) -> Void)?
    var onCommandLine: (() -> Void)?
    /// The keymap overlay (SN-503).
    var onHelp: (() -> Void)?
    /// Export and copy (SN-401, SN-402).
    var onExport: ((Effect) -> Void)?
    /// `:rename-plan` (SN-303).
    var onRenamePlan: (() -> Void)?
    /// `:excluded` (SN-305).
    var onListExcluded: (([String]) -> Void)?
    /// Effects the storyboard carries out (SN-301).
    var onStoryboard: ((Effect) -> Void)?
    /// The app zips the config folder and writes a setting.
    var onExportConfig: ((String) -> Void)?
    var onSetOption: ((String, String) -> Void)?

    /// Snapping while drawing, from the config's `snap`.
    var snap = true

    /// Zoom and centre, kept across steps.
    var viewport = Viewport()
    /// Space is held: drags pan instead of using the tool.
    var spaceHeld = false
    /// The last view point of a space-drag.
    var panFrom: CGPoint?

    var matcher = KeyMatcher(keymap: DefaultKeymap.keymap)
    var keyTimeout: DispatchWorkItem?
    private var capture: (url: URL, image: CGImage)?
    private var base: (key: BaseKey, image: CGImage)?
    /// The base as the screen draws it: halved `level` times.
    private var shown: (base: CGImage, level: Int, image: CGImage)?

    private struct BaseKey: Equatable {
        let url: URL
        let redactions: [Annotation]
        let factor: CGFloat
        /// A changed `blur` in the styles file blurs again.
        let styles: Styles
    }

    static let handleSize: CGFloat = 8

    override var isFlipped: Bool { true }

    /// The capture, in a view just below this one (SN-606); it follows this
    /// view's frame and visibility.
    let captureView = CaptureView()

    override var isHidden: Bool {
        didSet {
            captureView.isHidden = isHidden
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        captureView.removeFromSuperview()
        guard let superview else {
            return
        }
        captureView.frame = frame
        captureView.isHidden = isHidden
        superview.addSubview(captureView, positioned: .below, relativeTo: self)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        captureView.frame = frame
    }

    override var acceptsFirstResponder: Bool { true }

    /// The current step's image in this view, `nil` without one.
    var viewportFrame: Viewport.Frame? {
        guard let step = editor?.state.currentStep, let image = image(for: step) else {
            return nil
        }
        return Viewport.Frame(
            imageSize: CGSize(width: image.width, height: image.height),
            factor: stepTransform.factor,
            viewSize: bounds.size,
            backingScale: window?.backingScaleFactor ?? 2
        )
    }

    /// Image pixels to view points for the current step, `nil` without one.
    var viewTransform: ViewTransform? {
        viewportFrame.map { viewport.transform(in: $0) }
    }

    var stepTransform: StepTransform {
        StepTransform(scale: editor?.state.currentStep?.scale)
    }

    /// A view point in the current step's stored pixels.
    func stored(_ point: CGPoint) -> CGPoint? {
        viewTransform.map { stepTransform.toStored($0.toImage(point)) }
    }

    /// A stored pixel of the current step in view points.
    func viewPoint(_ point: CGPoint) -> CGPoint {
        viewTransform.map { view(point, $0) } ?? point
    }

    /// View points as stored pixels, for tolerances and thresholds.
    func storedLength(_ points: CGFloat) -> CGFloat {
        guard let view = viewTransform else {
            return points
        }
        return view.toImage(length: points) / stepTransform.factor
    }

    private func view(_ point: CGPoint, _ transform: ViewTransform) -> CGPoint {
        transform.toView(stepTransform.toImage(point))
    }

    private func view(_ rect: CGRect, _ transform: ViewTransform) -> CGRect {
        transform.toView(stepTransform.toImage(rect))
    }

    /// Captures renamed under the same names: the cached images are stale.
    func clearImageCaches() {
        capture = nil
        base = nil
        shown = nil
        needsDisplay = true
    }

    func image(for step: CaseStep) -> CGImage? {
        if let capture, capture.url == step.url {
            return capture.image
        }
        guard let image = Renderer.loadImage(at: step.url) else {
            return nil
        }
        capture = (step.url, image)
        return image
    }

    private func baseImage(for scene: Scene, url: URL) -> CGImage {
        let key = BaseKey(
            url: url,
            redactions: scene.items.filter {
                if case .blur = $0.shape {
                    return true
                }
                return false
            },
            factor: scene.transform.factor,
            styles: scene.styles
        )
        if let base, base.key == key {
            return base.image
        }
        let image = Renderer.base(scene)
        base = (key, image)
        return image
    }

    /// The base for the screen (SN-606): halved to the smallest power of
    /// two that still has a pixel for every device pixel it covers, so the
    /// GPU gets a small texture; at full size the base itself, as a copy
    /// would only double the memory. Made again only when the base or the
    /// level changes.
    private func displayImage(_ base: CGImage, deviceScale: CGFloat) -> CGImage {
        let level = deviceScale >= 1 ? 0 : Int(log2(1 / deviceScale).rounded(.down))
        guard level > 0 else {
            shown = nil
            return base
        }
        if let shown, shown.base === base, shown.level == level {
            return shown.image
        }
        let image = Renderer.displayCopy(of: base, factor: 1 / CGFloat(1 << level))
        shown = (base, level, image)
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        let started = Date()
        defer {
            TestHooks.report("canvas draw", since: started)
        }
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        guard let editor else {
            captureView.show(nil, in: .zero, nearest: false)
            drawMessage("Open a case folder (cmd-o)")
            return
        }
        let state = editor.state
        guard let step = state.currentStep, let image = image(for: step), let transform = viewTransform else {
            captureView.show(nil, in: .zero, nearest: false)
            drawMessage(editor.state.document.steps.isEmpty ? "No images in \(state.document.caseID)" : "Cannot decode the image")
            return
        }
        let preview = gesture?.preview(in: state)
        let items = textEdit?.preview(in: state) ?? preview?.items ?? state.items
        let scene = Scene(
            image: image,
            items: items,
            numbers: state.counterNumbers(items: items),
            transform: stepTransform,
            styles: state.styles
        )
        // The base (capture and redactions) comes from the saved items only:
        // a region being drawn, moved or resized shows as an outline and is
        // blurred on release, so Core Image never runs per mouse move.
        var saved = scene
        saved.items = state.items
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // Past two device pixels per image pixel the pixels show, for
        // placing things exactly.
        let backing = window?.backingScaleFactor ?? 2
        captureView.show(
            displayImage(baseImage(for: saved, url: step.url), deviceScale: transform.scale * backing),
            in: transform.toView(imageRect),
            nearest: transform.scale * backing > 2
        )
        context.saveGState()
        context.translateBy(x: transform.offset.x, y: transform.offset.y)
        context.scaleBy(x: transform.scale, y: transform.scale)
        Renderer.drawAnnotations(scene, in: context)
        context.restoreGState()
        TestHooks.endTiming("launch to first paint")
        drawPendingRedactions(items, saved: state.items, transform: transform, in: context)
        if let crop = preview?.crop ?? state.crop {
            drawCrop(crop, editing: state.tool == .crop, imageRect: transform.toView(imageRect), transform: transform, in: context)
        }
        drawSelection(scene.items, state: state, transform: transform, in: context)
        if let marquee = preview?.marquee {
            let rect = view(marquee, transform)
            context.setFillColor(Brand.accent.withAlphaComponent(0.12).cgColor)
            context.fill(rect)
            context.setStrokeColor(Brand.accent.cgColor)
            context.setLineWidth(1)
            context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        }
        drawGuides(gesture?.guides ?? [], imageRect: transform.toView(imageRect), transform: transform, in: context)
    }

    /// The whole capture stays on screen and export cuts (SN-207): outside
    /// the crop is darkened with its border and handles while the crop tool
    /// is active, and dimmed lightly otherwise so the exported area shows.
    private func drawCrop(
        _ crop: CGRect,
        editing: Bool,
        imageRect: CGRect,
        transform: ViewTransform,
        in context: CGContext
    ) {
        let box = view(crop, transform)
        context.saveGState()
        context.addRect(imageRect)
        context.addRect(box)
        context.setFillColor(NSColor(white: 0, alpha: editing ? 0.6 : 0.35).cgColor)
        context.fillPath(using: .evenOdd)
        context.setLineWidth(1)
        context.setStrokeColor(editing ? Brand.accent.cgColor : NSColor(white: 1, alpha: 0.4).cgColor)
        context.stroke(box.insetBy(dx: -0.5, dy: -0.5))
        if editing {
            let size = Self.handleSize
            context.setStrokeColor(Brand.accent.cgColor)
            for handle in Geometry.handles(of: crop) {
                let point = view(handle.point, transform)
                let square = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(square)
                context.stroke(square.insetBy(dx: 0.5, dy: 0.5))
            }
        }
        context.restoreGState()
    }

    /// Regions whose blur is not in the base yet: frosted, dashed outline.
    private func drawPendingRedactions(
        _ items: [Annotation],
        saved: [Annotation],
        transform: ViewTransform,
        in context: CGContext
    ) {
        let savedShapes = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0.shape) })
        for item in items {
            guard case .blur(let rect, _) = item.shape, savedShapes[item.id] != item.shape else {
                continue
            }
            let box = view(rect, transform)
            context.setFillColor(NSColor(white: 1, alpha: 0.35).cgColor)
            context.fill(box)
            context.saveGState()
            context.setStrokeColor(Brand.accent.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [5, 3])
            context.stroke(box.insetBy(dx: 0.75, dy: 0.75))
            context.restoreGState()
        }
    }

    private func drawSelection(
        _ items: [Annotation],
        state: EditorState,
        transform: ViewTransform,
        in context: CGContext
    ) {
        let selected = items.filter { state.selection.contains($0.id) }
        context.setStrokeColor(Brand.accent.cgColor)
        context.setLineWidth(1)
        for item in selected {
            let bounds = Geometry.bounds(of: item.shape, style: state.styles.style(for: item.preset))
            guard !bounds.isNull else {
                continue
            }
            context.stroke(view(bounds, transform).insetBy(dx: -2.5, dy: -2.5))
        }
        guard selected.count == 1, let item = selected.first else {
            return
        }
        let size = Self.handleSize
        for handle in Geometry.handles(of: item.shape) {
            let point = view(handle.point, transform)
            let square = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(square)
            context.stroke(square.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    private func drawGuides(
        _ guides: [Snapper.Guide],
        imageRect: CGRect,
        transform: ViewTransform,
        in context: CGContext
    ) {
        guard !guides.isEmpty else {
            return
        }
        context.setStrokeColor(Brand.accent.cgColor)
        context.setLineWidth(1)
        for guide in guides {
            switch guide.axis {
            case .x:
                let x = view(CGPoint(x: guide.position, y: 0), transform).x.rounded() + 0.5
                context.move(to: CGPoint(x: x, y: imageRect.minY))
                context.addLine(to: CGPoint(x: x, y: imageRect.maxY))
            case .y:
                let y = view(CGPoint(x: 0, y: guide.position), transform).y.rounded() + 0.5
                context.move(to: CGPoint(x: imageRect.minX, y: y))
                context.addLine(to: CGPoint(x: imageRect.maxX, y: y))
            }
        }
        context.strokePath()
    }

    private func drawMessage(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor(white: 1, alpha: 0.55),
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
