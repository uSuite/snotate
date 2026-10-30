import AppKit
import SNotateCore

/// Keys go through the keymap and mouse drags through `Gesture`; both end
/// as Commands on the editor, so the view decides nothing itself.
extension CanvasView: NSMenuItemValidation {
    /// Hit slop, handle grab radius and snapping distance, in view points.
    static let tolerance: CGFloat = 4
    static let snapDistance: CGFloat = 6
    /// Drags shorter than this many image pixels are clicks.
    static let minimumDrag: CGFloat = 4

    func perform(_ command: Command, count: Int? = nil) {
        let effects = editor?.perform(command, count: count) ?? []
        window?.invalidateCursorRects(for: self)
        for effect in effects {
            switch effect {
            case .beginTextEdit(let id):
                if let state = editor?.state, let edit = TextEdit(existing: id, in: state) {
                    beginEditing(edit)
                }
            case .zoom where editor?.state.mode == .storyboard:
                onStoryboard?(effect)
            case .zoom(let request):
                zoom(request)
            case .pan(let direction, let big):
                pan(direction, big: big)
            case .siblingCase(let offset):
                onSiblingCase?(offset)
            case .commandLine:
                onCommandLine?()
            case .help:
                onHelp?()
            case .exportConfig(let path):
                onExportConfig?(path)
            case .setOption(let key, let value):
                onSetOption?(key, value)
            case .beginCaptionEdit, .storyboardMove:
                onStoryboard?(effect)
            case .listExcluded(let files):
                onListExcluded?(files)
            case .renamePlan:
                onRenamePlan?()
            case .exportCase, .exportStep, .copyStep:
                onExport?(effect)
            case .sidecarChanged, .message, .memoChanged, .removeStep, .restoreStep:
                break
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard editor != nil, let key = KeyTranslator.key(for: event) else {
            super.keyDown(with: event)
            return
        }
        if key == Key("space") {
            // Held, not bound: space-drag pans whatever the tool (SN-502).
            if !spaceHeld {
                spaceHeld = true
                window?.invalidateCursorRects(for: self)
            }
            return
        }
        if gesture != nil, key == Key("esc") {
            if gesture?.kind == .zoomArea {
                perform(.zoomArea)
            }
            gesture = nil
            return
        }
        keyTimeout?.cancel()
        switch matcher.feed(key) {
        case .matched(let invocation):
            perform(invocation.command, count: invocation.count)
        case .pending:
            // vim's timeoutlen: a bound prefix such as g fires after a pause.
            keyTimeout = MainQueue.after(1) { [weak self] in
                guard let self, let invocation = self.matcher.flush() else {
                    return
                }
                self.perform(invocation.command, count: invocation.count)
            }
        case .unmatched:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        guard KeyTranslator.key(for: event) == Key("space") else {
            super.keyUp(with: event)
            return
        }
        spaceHeld = false
        panFrom = nil
        window?.invalidateCursorRects(for: self)
    }

    override func resignFirstResponder() -> Bool {
        // A space released in another window must not leave panning on.
        spaceHeld = false
        panFrom = nil
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        if spaceHeld {
            panFrom = convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.set()
            return
        }
        // A click outside the text being typed commits it first.
        endEditing()
        window?.makeFirstResponder(self)
        guard let editor, let point = stored(convert(event.locationInWindow, from: nil)) else {
            return
        }
        if event.clickCount == 2, editor.state.tool == .select,
            let hit = Geometry.topmost(at: point, in: editor.state.items, styles: editor.state.styles, tolerance: storedLength(Self.tolerance)),
            editor.state.items.contains(where: { $0.id == hit && $0.shape.isText })
        {
            perform(.select([hit]))
            perform(.edit)
            return
        }
        let (gesture, commands) = Gesture.begin(
            at: point,
            in: editor.state,
            shift: event.modifierFlags.contains(.shift),
            tolerance: storedLength(Self.tolerance),
            handleRadius: storedLength(Self.handleSize)
        )
        commands.forEach { perform($0) }
        self.gesture = gesture
    }

    override func mouseDragged(with event: NSEvent) {
        if let from = panFrom {
            let point = convert(event.locationInWindow, from: nil)
            panFrom = point
            pan(by: CGVector(dx: point.x - from.x, dy: point.y - from.y))
            return
        }
        follow(event)
    }

    override func mouseUp(with event: NSEvent) {
        if panFrom != nil {
            mouseDragged(with: event)
            panFrom = nil
            window?.invalidateCursorRects(for: self)
            return
        }
        follow(event)
        guard let editor, let gesture else {
            return
        }
        let minimum = Self.minimumDrag / stepTransform.factor
        let commands = gesture.finish(in: editor.state, minimumLength: minimum)
        let text = gesture.newText(in: editor.state, minimumLength: minimum)
        self.gesture = nil
        commands.forEach { perform($0) }
        if let text {
            beginEditing(TextEdit(new: text))
        }
    }

    private func follow(_ event: NSEvent) {
        guard let editor, gesture != nil, let point = stored(convert(event.locationInWindow, from: nil)) else {
            return
        }
        gesture?.drag(
            to: point,
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            in: editor.state,
            snapThreshold: snap ? storedLength(Self.snapDistance) : nil
        )
    }

    override func resetCursorRects() {
        if spaceHeld {
            addCursorRect(bounds, cursor: .openHand)
        } else if let state = editor?.state, state.tool != .select || state.zoomArmed {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    /// Undo and redo while typing commit the text first, so on new text
    /// cmd-z cancels it.
    @objc func undo(_ sender: Any?) {
        endEditing()
        perform(.undo)
    }

    @objc func redo(_ sender: Any?) {
        endEditing()
        perform(.redo)
    }

    @objc(selectAll:) func selectAllItems(_ sender: Any?) {
        perform(.selectAll)
    }

    @objc func delete(_ sender: Any?) {
        perform(.delete)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let state = editor?.state else {
            return false
        }
        switch menuItem.action {
        case #selector(undo(_:)):
            menuItem.title = state.undoLabel.map { "Undo \($0)" } ?? "Undo"
            return state.undoLabel != nil || textEdit != nil
        case #selector(redo(_:)):
            menuItem.title = state.undo.redoLabel.map { "Redo \($0)" } ?? "Redo"
            return state.undo.redoLabel != nil
        case #selector(delete(_:)):
            return Dispatcher.isAvailable(.delete, in: state)
        case #selector(selectAllItems(_:)):
            return Dispatcher.isAvailable(.selectAll, in: state)
        default:
            return true
        }
    }
}
