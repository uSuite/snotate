import CoreGraphics
import Foundation

/// One press, drag and release on the canvas, in stored pixels. `begin`
/// decides what the press means from the tool and what is under it (and
/// returns the selection commands a press implies), `drag` follows the
/// pointer with snapping and shift, `preview` is what to draw meanwhile, and
/// `finish` is the one command the release commits, so a drag is one undo
/// entry (DECISIONS 2026-10-26). The view only converts points and draws.
public struct Gesture: Sendable {
    public enum Kind: Sendable, Equatable {
        /// A new arrow, rectangle, ellipse, counter or text; a counter and
        /// text land where the press is released, and text dragged out gets
        /// a leader back to the press point. Text is committed by `TextEdit`,
        /// not by `finish`.
        case draw(Tool)
        case move(Set<UUID>)
        case handle(UUID, Handle)
        /// `base` is the selection kept by a shift-marquee.
        case marquee(base: Set<UUID>)
        /// The step's crop (SN-207): a new one, or the current one moved or
        /// resized by a handle, each committed as one `setCrop`.
        case cropDraw
        case cropMove(CGRect)
        case cropHandle(Handle, CGRect)
        /// An armed `zoom-area`: the area to zoom to, or a click to zoom in.
        case zoomArea
    }

    /// What to draw during the gesture.
    public struct Preview: Sendable {
        /// The current step's items as they would be after the release.
        public let items: [Annotation]
        public let marquee: CGRect?
        /// The crop as it would be after the release, for crop gestures.
        public let crop: CGRect?

        init(items: [Annotation], marquee: CGRect? = nil, crop: CGRect? = nil) {
            self.items = items
            self.marquee = marquee
            self.crop = crop
        }
    }

    public let kind: Kind
    public let start: CGPoint
    public private(set) var end: CGPoint
    /// Where the pointer is, before snapping: whether a press became a drag
    /// is the pointer's distance, not the snapped end's.
    private var pointer: CGPoint
    public private(set) var guides: [Snapper.Guide] = []
    private var shift = false
    private var option = false

    init(kind: Kind, start: CGPoint) {
        self.kind = kind
        self.start = start
        end = start
        pointer = start
    }

    /// `tolerance` is the hit slop and `handleRadius` the grab radius of a
    /// handle, both in stored pixels.
    public static func begin(
        at point: CGPoint,
        in state: EditorState,
        shift: Bool,
        tolerance: CGFloat,
        handleRadius: CGFloat
    ) -> (gesture: Gesture?, commands: [Command]) {
        guard state.currentStep != nil else {
            return (nil, [])
        }
        if state.zoomArmed {
            return (Gesture(kind: .zoomArea, start: point), [])
        }
        switch state.tool {
        case .arrow, .rectangle, .ellipse, .counter, .text, .highlight, .blur:
            return (Gesture(kind: .draw(state.tool), start: point), [])
        case .crop:
            if let crop = state.crop {
                if let handle = Geometry.handles(of: crop).first(where: {
                    hypot($0.point.x - point.x, $0.point.y - point.y) <= handleRadius
                }) {
                    return (Gesture(kind: .cropHandle(handle.handle, crop), start: point), [])
                }
                if crop.contains(point) {
                    return (Gesture(kind: .cropMove(crop), start: point), [])
                }
            }
            return (Gesture(kind: .cropDraw, start: point), [])
        case .select:
            let items = state.items
            if state.selection.count == 1,
                let item = items.first(where: { state.selection.contains($0.id) }),
                let handle = Geometry.handles(of: item.shape).first(where: {
                    hypot($0.point.x - point.x, $0.point.y - point.y) <= handleRadius
                })
            {
                return (Gesture(kind: .handle(item.id, handle.handle), start: point), [])
            }
            guard let hit = Geometry.topmost(at: point, in: items, styles: state.styles, tolerance: tolerance) else {
                return (Gesture(kind: .marquee(base: shift ? state.selection : []), start: point), [])
            }
            if shift {
                var selection = state.selection
                if selection.contains(hit) {
                    selection.remove(hit)
                } else {
                    selection.insert(hit)
                }
                let gesture = selection.contains(hit) ? Gesture(kind: .move(selection), start: point) : nil
                return (gesture, [.toggleSelect(hit)])
            }
            if state.selection.contains(hit) {
                return (Gesture(kind: .move(state.selection), start: point), [])
            }
            return (Gesture(kind: .move([hit]), start: point), [.select([hit])])
        }
    }

    /// `snapThreshold` in stored pixels, `nil` when snapping is off. Shift
    /// constrains (45 degrees, squares, aspect) and turns snapping off for
    /// what it constrains; option draws and resizes about the centre.
    public mutating func drag(
        to point: CGPoint,
        shift: Bool,
        option: Bool = false,
        in state: EditorState,
        snapThreshold: CGFloat?
    ) {
        self.shift = shift
        self.option = option
        guides = []
        end = point
        pointer = point
        guard let threshold = snapThreshold, let canvas = Self.canvas(state) else {
            return
        }
        switch kind {
        case .draw where !shift, .cropDraw where !shift, .cropHandle where !shift:
            let snapper = Snapper(imageSize: canvas, targets: Snapper.targets(in: state.items, excluding: [], styles: state.styles, outlines: true), threshold: threshold)
            (end, guides) = snapper.snap(point)
        case .handle(let id, let handle) where !(shift && [.start, .end].contains(handle)):
            let snapper = Snapper(imageSize: canvas, targets: Snapper.targets(in: state.items, excluding: [id], styles: state.styles, outlines: true), threshold: threshold)
            (end, guides) = snapper.snap(point)
        case .move(let ids):
            let moving = state.items.filter { ids.contains($0.id) }
            let bounds = moving.map { Geometry.bounds(of: $0.shape, style: state.styles.style(for: $0.preset)) }
                .filter { !$0.isNull }
                .reduce(CGRect.null) { $0.union($1) }
            guard !bounds.isNull else {
                return
            }
            let snapper = Snapper(imageSize: canvas, targets: Snapper.targets(in: state.items, excluding: ids, styles: state.styles), threshold: threshold)
            let moved = bounds.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            let snapped = snapper.snap(moved)
            end = CGPoint(x: point.x + snapped.rect.minX - moved.minX, y: point.y + snapped.rect.minY - moved.minY)
            guides = snapped.guides
        case .cropMove(let crop):
            let snapper = Snapper(imageSize: canvas, targets: Snapper.targets(in: state.items, excluding: [], styles: state.styles, outlines: true), threshold: threshold)
            let moved = crop.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            let snapped = snapper.snap(moved)
            end = CGPoint(x: point.x + snapped.rect.minX - moved.minX, y: point.y + snapped.rect.minY - moved.minY)
            guides = snapped.guides
        default:
            break
        }
    }

    public func preview(in state: EditorState) -> Preview {
        var items = state.items
        switch kind {
        case .draw(let tool):
            items.append(Annotation(shape: drawnShape(tool, in: state), preset: state.activePreset))
        case .move(let ids):
            items.update(ids) { $0.shape = Geometry.moved($0.shape, by: offset) }
        case .handle(let id, let handle):
            items.update([id]) { item in
                item.shape = Geometry.dragging(item.shape, handle: handle, to: end, constrain: shift, fromCentre: option)
            }
        case .marquee, .zoomArea:
            return Preview(items: items, marquee: marqueeRect)
        case .cropDraw, .cropMove, .cropHandle:
            return Preview(items: items, crop: cropRect(in: state))
        }
        return Preview(items: items)
    }

    /// The command the release commits; none for a click that did not move,
    /// an arrow shorter than `minimumLength` stored pixels or a shape with a
    /// side shorter than that.
    public func finish(in state: EditorState, minimumLength: CGFloat) -> [Command] {
        switch kind {
        case .draw(let tool):
            let shape = drawnShape(tool, in: state)
            // A click is judged by the pointer, not the snapped end, which
            // may have jumped further than the threshold.
            let moved = pointerMoved(minimumLength)
            switch shape {
            case .arrow(let from, let to, _):
                guard moved, hypot(to.x - from.x, to.y - from.y) >= minimumLength else {
                    return []
                }
            case .rectangle(let rect, _), .ellipse(let rect, _), .highlight(let rect, _), .blur(let rect, _):
                guard moved, min(rect.width, rect.height) >= minimumLength else {
                    return []
                }
            case .counter:
                break
            case .text:
                return []
            default:
                return []
            }
            return [.add(Annotation(shape: shape, preset: state.activePreset))]
        case .move(let ids):
            // Judged by the pointer: snapping alone must not move a shape
            // that was only clicked to select it.
            guard pointerMoved(minimumLength), offset != .zero else {
                return []
            }
            return [.move(ids, by: offset)]
        case .handle(let id, _):
            guard pointerMoved(minimumLength), let before = state.items.first(where: { $0.id == id }),
                let after = preview(in: state).items.first(where: { $0.id == id }),
                after.shape != before.shape
            else {
                return []
            }
            return [.setShape(id, after.shape)]
        case .marquee(let base):
            let hits = Geometry.marquee(marqueeRect, in: state.items, styles: state.styles)
            return [.select(base.union(hits))]
        case .cropDraw, .cropMove, .cropHandle:
            // The Dispatcher clamps the crop to the image.
            guard pointerMoved(minimumLength), let rect = cropRect(in: state),
                min(rect.width, rect.height) >= minimumLength
            else {
                return []
            }
            if case .cropMove(let crop) = kind, crop == rect {
                return []
            }
            return [.setCrop(rect)]
        case .zoomArea:
            let rect = marqueeRect
            guard pointerMoved(minimumLength), min(rect.width, rect.height) >= minimumLength else {
                return [.zoomTo(CGRect(origin: start, size: .zero))]
            }
            return [.zoomTo(rect)]
        }
    }

    /// The empty text a text-tool gesture starts, for `TextEdit(new:)`; a
    /// leader only when the drag was at least `minimumLength` long.
    public func newText(in state: EditorState, minimumLength: CGFloat) -> Annotation? {
        guard kind == .draw(.text) else {
            return nil
        }
        let dragged = pointerMoved(minimumLength)
        return Annotation(
            shape: .text(at: end, text: "", pill: state.filled.contains(.text), leader: dragged ? start : nil),
            preset: state.activePreset
        )
    }

    private func pointerMoved(_ minimumLength: CGFloat) -> Bool {
        hypot(pointer.x - start.x, pointer.y - start.y) >= minimumLength
    }

    private var offset: CGVector {
        CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private func drawnShape(_ tool: Tool, in state: EditorState) -> Shape {
        switch tool {
        case .rectangle:
            return .rectangle(drawnRect, fill: state.filled.contains(.rectangle))
        case .ellipse:
            return .ellipse(drawnRect, fill: state.filled.contains(.ellipse))
        case .highlight:
            return .highlight(drawnRect, spotlight: state.filled.contains(.highlight))
        case .blur:
            return .blur(drawnRect, pixelate: state.filled.contains(.blur))
        case .counter:
            return .counter(at: end)
        case .text:
            return .text(at: end, text: "", pill: state.filled.contains(.text), leader: pointer == start ? nil : start)
        default:
            return .arrow(from: start, to: shift ? Geometry.snapped45(end, about: start) : end, curve: nil)
        }
    }

    /// Corner to corner, a square with shift, about the start with option.
    private var drawnRect: CGRect {
        rect(aspect: shift ? 1 : nil)
    }

    /// Corner to corner, kept to `aspect` (width over height) when given by
    /// the larger of the two moves, about the start with option.
    private func rect(aspect: CGFloat?) -> CGRect {
        var dx = end.x - start.x
        var dy = end.y - start.y
        if let aspect, aspect > 0 {
            if abs(dx) / aspect >= abs(dy) {
                dy = (dy < 0 ? -1 : 1) * abs(dx) / aspect
            } else {
                dx = (dx < 0 ? -1 : 1) * abs(dy) * aspect
            }
        }
        if option {
            return CGRect(x: start.x - abs(dx), y: start.y - abs(dy), width: 2 * abs(dx), height: 2 * abs(dy))
        }
        return CGRect(x: start.x, y: start.y, width: dx, height: dy).standardized
    }

    /// The crop a crop gesture makes: drawn (shift locks the image's
    /// aspect), moved, or resized by a handle (shift keeps its aspect).
    private func cropRect(in state: EditorState) -> CGRect? {
        switch kind {
        case .cropDraw:
            let aspect = shift ? Self.canvas(state).map { CGFloat($0.width) / CGFloat($0.height) } : nil
            return rect(aspect: aspect)
        case .cropMove(let crop):
            return crop.offsetBy(dx: offset.dx, dy: offset.dy)
        case .cropHandle(let handle, let crop):
            return Geometry.resized(crop, handle: handle, to: end, constrain: shift, fromCentre: option)
        default:
            return nil
        }
    }

    private var marqueeRect: CGRect {
        CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y).standardized
    }

    /// The current step's size in stored pixels.
    static func canvas(_ state: EditorState) -> PixelSize? {
        guard let step = state.currentStep else {
            return nil
        }
        let recorded = state.sidecarIndex.flatMap { state.document.sidecar.steps[$0].size }
        guard let size = recorded ?? step.size else {
            return nil
        }
        // A flagged step is drawn unscaled, so its own size is the canvas.
        if case .mismatch = step.scale, let actual = step.size {
            return actual
        }
        return size
    }
}
