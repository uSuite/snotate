import AppKit
import SNotateCore

/// A flipped layer over the canvas whose coordinates are the current
/// step's stored pixels, so the text field inside it uses the renderer's own
/// font size and line height and is scaled the way the rendered text is:
/// a field set at the zoomed point size would pick another optical size of
/// the system font and run wider than the glyphs under it. Clicks outside
/// the field fall through to the canvas.
final class StoredPixelLayer: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// In-place text editing: a `TextEdit` in the core, an `InPlaceTextView`
/// for the caret over the text the canvas renders.
extension CanvasView {
    func beginEditing(_ edit: TextEdit) {
        endEditing()
        textEdit = edit
        let field = InPlaceTextView(fontSize: 12, lineHeight: 12)
        field.onChange = { [weak self] text in
            self?.typed(text)
        }
        field.onCommit = { [weak self] in
            self?.endEditing()
        }
        field.string = edit.text
        let layer = StoredPixelLayer()
        layer.addSubview(field)
        addSubview(layer)
        textLayer = layer
        textField = field
        placeField()
        window?.makeFirstResponder(field)
        field.setSelectedRange(NSRange(location: (edit.text as NSString).length, length: 0))
    }

    /// Commits the edit in progress, if any.
    func endEditing() {
        guard let edit = textEdit else {
            return
        }
        textEdit = nil
        textLayer?.removeFromSuperview()
        textLayer = nil
        textField = nil
        window?.makeFirstResponder(self)
        edit.commit().forEach { perform($0) }
    }

    private func typed(_ text: String) {
        guard var edit = textEdit else {
            return
        }
        let commands = edit.update(text)
        textEdit = edit
        commands.forEach { perform($0) }
        placeField()
    }

    /// Maps the layer to stored pixels and puts the field on the text's
    /// top-left corner at the preset's font size.
    func placeField() {
        guard let field = textField, let layer = textLayer, let edit = textEdit, let state = editor?.state,
            let transform = viewTransform,
            let item = edit.preview(in: state).first(where: { $0.id == edit.annotationID }),
            case .text(let at, _, _, _) = item.shape
        else {
            return
        }
        let scale = transform.scale * stepTransform.factor
        layer.frame = bounds
        layer.bounds = CGRect(
            x: -transform.offset.x / scale,
            y: -transform.offset.y / scale,
            width: bounds.width / scale,
            height: bounds.height / scale
        )
        let style = state.styles.style(for: item.preset)
        field.setFont(size: style.fontSize, lineHeight: TextLayout(text: "", fontSize: style.fontSize).lineHeight)
        field.setFrameOrigin(at)
        needsDisplay = true
    }
}
