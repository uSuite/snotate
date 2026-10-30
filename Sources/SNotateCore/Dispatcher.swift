import CoreGraphics
import Foundation

/// What a window shows of an open case: the document, the current step, the
/// selection on it, the preset for new annotations and the undo history.
/// Only the `Dispatcher` changes it.
public struct EditorState: Sendable {
    public internal(set) var document: CaseDocument
    /// Index into `document.steps`, `nil` when the case has no images.
    public internal(set) var current: Int?
    /// Annotation ids on the current step.
    public internal(set) var selection: Set<UUID> = []
    public internal(set) var activePreset = 1
    public internal(set) var tool = Tool.select
    /// Drawing tools whose next shapes are filled; for the session only.
    public internal(set) var filled: Set<Tool> = []
    public var styles = Styles.builtIn
    public internal(set) var undo = UndoStack()
    /// The next drag zooms to its area (`zoom-area`) instead of using the
    /// tool; any other command disarms it.
    public internal(set) var zoomArmed = false
    /// The single step or the storyboard (SN-301); the storyboard's
    /// selected frame is the current step.
    public internal(set) var mode = ViewMode.step
    /// The step was opened from the storyboard, so esc goes back to it once
    /// the tool and selection are dropped.
    public internal(set) var openedFromStoryboard = false
    /// Steps removed with `dd`, newest last (SN-309). Kept apart from undo,
    /// since the file leaving reloads the case and a reload clears undo;
    /// `cmd-z` reaches the newest once undo is empty.
    public internal(set) var removed: [RemovedStep] = []

    public init(
        document: CaseDocument,
        file: String? = nil
    ) {
        self.document = document
        let steps = document.steps
        current = file.flatMap { file in steps.firstIndex { $0.file == file } } ?? (steps.isEmpty ? nil : 0)
    }

    public var currentStep: CaseStep? {
        current.map { document.steps[$0] }
    }

    /// What `cmd-z` undoes next: the history, then the newest removed step.
    public var undoLabel: String? {
        undo.undoLabel ?? (removed.isEmpty ? nil : "Remove Step")
    }

    /// The current step's entry in `document.sidecar.steps`.
    var sidecarIndex: Int? {
        currentStep.flatMap { step in document.sidecar.steps.firstIndex { $0.file == step.file } }
    }

    /// The current step's crop, in stored pixels.
    public var crop: CGRect? {
        sidecarIndex.flatMap { document.sidecar.steps[$0].crop }
    }

    /// Annotations on the current step, in drawing order.
    public var items: [Annotation] {
        sidecarIndex.map { document.sidecar.steps[$0].items } ?? []
    }

    /// Counter numbers for the whole case with the current step showing
    /// `items`, so a counter being placed shows the number it will get and
    /// the ones after it their new numbers.
    public func counterNumbers(items: [Annotation]) -> [UUID: Int] {
        var sidecar = document.sidecar
        if let index = sidecarIndex {
            sidecar.steps[index].items = items
        }
        return CounterNumbering.numbers(in: sidecar, present: Set(document.steps.map(\.file)))
    }

    var snapshot: UndoStack.Snapshot {
        UndoStack.Snapshot(
            sidecar: document.sidecar,
            memo: document.memo,
            step: currentStep?.file,
            selection: selection
        )
    }
}

public enum Effect: Sendable, Equatable {
    /// The sidecar changed and should be saved.
    case sidecarChanged
    /// Something to tell the user, such as why an edit was refused.
    case message(String)
    /// The canvas should open this text annotation for editing.
    case beginTextEdit(UUID)
    /// The canvas should change its zoom (SN-502).
    case zoom(ZoomRequest)
    /// The canvas should pan, when the image overflows: arrow keys with
    /// nothing selected.
    case pan(Command.Direction, big: Bool)
    /// The window should open the case this many siblings away.
    case siblingCase(Int)
    /// The window should open its `:` line.
    case commandLine
    /// The window should show or hide the keymap overlay (SN-503).
    case help
    /// The window should show the rename plan for confirmation (SN-303).
    case renamePlan
    /// The memo changed and should be written now (SN-302).
    case memoChanged
    /// The storyboard should open the current step's caption for editing.
    case beginCaptionEdit
    /// The storyboard should move the selected frame; up and down need its
    /// columns.
    case storyboardMove(Command.Direction)
    /// The app should list these excluded files and put them on the
    /// clipboard, for the author to delete (SN-305).
    case listExcluded([String])
    /// The editor should move this step's capture to the Trash and take it
    /// out of the sidecar and memo, or put a removed step back (SN-309).
    case removeStep(String)
    case restoreStep(RemovedStep)
    /// The window should export the case, or one step, into `notated/`, or
    /// put a step's export on the clipboard (SN-401, SN-402).
    case exportCase
    case exportStep(String)
    case copyStep(String)
    /// The app should zip the config folder to this path (empty: Desktop).
    case exportConfig(String)
    /// The app should check this setting, write it to the config file and
    /// apply it.
    case setOption(String, String)
}

public enum ViewMode: Sendable, Equatable {
    case step
    case storyboard
}

/// A zoom the canvas applies through its `Viewport`.
public enum ZoomRequest: Sendable, Equatable {
    /// Zoom steps about the view's centre, negative to zoom out.
    case steps(Int)
    case fit
    case actual
    /// An area in stored pixels to fill the view with.
    case area(CGRect)
    /// One step in, about this stored pixel.
    case inAt(CGPoint)
}

/// The single control point: applies an `Invocation` to `EditorState` and
/// returns the effects the window needs. Pure, so every command is tested
/// without a window.
public enum Dispatcher {
    public static func apply(
        _ invocation: Invocation<Command>,
        to state: inout EditorState
    ) -> [Effect] {
        let command = invocation.command
        if !command.isTextEdit {
            state.undo.endCoalescing()
        }
        let armed = state.zoomArmed
        state.zoomArmed = false
        // These work in a case without images too.
        switch command {
        case .caseNext:
            return [.siblingCase(invocation.times)]
        case .casePrevious:
            return [.siblingCase(-invocation.times)]
        case .commandLine:
            return [.commandLine]
        case .help:
            return [.help]
        case .renamePlan:
            return [.renamePlan]
        case .exportCase:
            return [.exportCase]
        case .exportStep, .copyStep:
            guard let step = state.currentStep else {
                return []
            }
            if step.excluded {
                return [.message("\(step.file) is excluded from export")]
            }
            return [command == .exportStep ? .exportStep(step.file) : .copyStep(step.file)]
        case .listExcluded:
            return [.listExcluded(state.document.sidecar.steps.filter(\.excluded).map(\.file))]
        case .exportConfig(let path):
            return [.exportConfig(path)]
        case .setOption(let key, let value):
            return [.setOption(key, value)]
        case .undo where state.undo.undoLabel == nil && !state.removed.isEmpty:
            // Also when the removed step was the last one (SN-309).
            return readOnly(state) ?? [.restoreStep(state.removed[state.removed.count - 1])]
        default:
            break
        }
        guard let current = state.current else {
            return []
        }
        let last = state.document.steps.count - 1
        let n = invocation.times

        if state.mode == .storyboard, let effects = storyboard(command, n: n, in: &state) {
            return effects
        }
        switch command {
        case .viewStoryboard, .editCaption:
            state.mode = .storyboard
            state.openedFromStoryboard = false
            state.selection = []
            return command == .editCaption ? [.beginCaptionEdit] : []
        case .viewStep:
            return []
        case .zoomIn:
            return [.zoom(.steps(n))]
        case .zoomOut:
            return [.zoom(.steps(-n))]
        case .zoomFit:
            return [.zoom(.fit)]
        case .zoomActual:
            return [.zoom(.actual)]
        case .zoomArea:
            state.zoomArmed = !armed
            return []
        case .zoomTo(let rect):
            return [.zoom(rect.width > 0 && rect.height > 0 ? .area(rect) : .inAt(rect.origin))]
        case .nudge(let direction, let big) where state.selection.isEmpty:
            // Arrow keys pan when there is nothing to nudge (DECISIONS 2026-10-27).
            return [.pan(direction, big: big)]
        case .next:
            go(to: min(current + n, last), in: &state)
        case .previous:
            go(to: max(current - n, 0), in: &state)
        case .first:
            go(to: 0, in: &state)
        case .last:
            go(to: last, in: &state)
        case .goTo(let step):
            go(to: max(0, min(step - 1, last)), in: &state)
        case .tool(let tool):
            // Asking for the select tool while selecting clears the
            // selection, so esc first drops a tool and then a selection.
            if tool == .select, state.tool == .select {
                if state.selection.isEmpty, state.openedFromStoryboard {
                    state.mode = .storyboard
                    state.openedFromStoryboard = false
                    return []
                }
                state.selection = []
            }
            if tool.fills, state.tool == tool {
                if state.filled.contains(tool) {
                    state.filled.remove(tool)
                } else {
                    state.filled.insert(tool)
                }
                let name = tool.rawValue.prefix(1).uppercased() + tool.rawValue.dropFirst()
                let on = state.filled.contains(tool)
                let mode: String
                switch tool {
                case .text:
                    mode = on ? "pill" : "plain"
                case .highlight:
                    mode = on ? "spotlight" : "marker"
                case .blur:
                    mode = on ? "pixelate" : "blur"
                default:
                    mode = on ? "filled" : "outline"
                }
                return [.message("\(name): \(mode)")]
            }
            state.tool = tool
        case .selectAll:
            state.selection = Set(state.items.map(\.id))
        case .deselect:
            state.selection = []
        case .select(let ids):
            state.selection = ids.intersection(state.items.map(\.id))
        case .toggleSelect(let id):
            if state.selection.contains(id) {
                state.selection.remove(id)
            } else if state.items.contains(where: { $0.id == id }) {
                state.selection.insert(id)
            }
        case .add(let annotation):
            return edit("Add", &state, select: [annotation.id]) { step in
                step.items.append(annotation)
            }
        case .setShape(let id, let shape):
            return edit("Change", &state) { step in
                step.items.update([id]) { $0.shape = shape }
            }
        case .editText(let id, let text):
            return edit("Edit Text", &state, coalesce: id) { step in
                step.items.update([id]) { item in
                    if case .text(let at, _, let pill, let leader) = item.shape {
                        item.shape = .text(at: at, text: text, pill: pill, leader: leader)
                    }
                }
            }
        case .move(let ids, let offset):
            return edit("Move", &state) { step in
                step.items.update(ids) { $0.shape = Geometry.moved($0.shape, by: offset) }
            }
        case .nudge(let direction, let big):
            // Image pixels, so a nudge on a 2x step is one pixel on screen.
            let pixels = CGFloat((big ? 10 : 1) * n) / StepTransform(scale: state.currentStep?.scale).factor
            let offset: CGVector
            switch direction {
            case .left:
                offset = CGVector(dx: -pixels, dy: 0)
            case .right:
                offset = CGVector(dx: pixels, dy: 0)
            case .up:
                offset = CGVector(dx: 0, dy: -pixels)
            case .down:
                offset = CGVector(dx: 0, dy: pixels)
            }
            let selection = state.selection
            return edit("Nudge", &state) { step in
                step.items.update(selection) { $0.shape = Geometry.moved($0.shape, by: offset) }
            }
        case .delete where state.tool == .crop:
            // With the crop tool, delete acts on what the tool works on.
            guard let index = state.sidecarIndex, state.document.sidecar.steps[index].crop != nil else {
                return []
            }
            return apply(Invocation(.setCrop(nil)), to: &state)
        case .cropPrevious:
            let document = state.document
            var crop: CGRect?
            for step in document.steps[..<current].reversed() {
                if let found = document.sidecar.steps.first(where: { $0.file == step.file })?.crop {
                    crop = found
                    break
                }
            }
            guard let crop else {
                return readOnly(state) ?? [.message("No earlier step has a crop")]
            }
            return apply(Invocation(.setCrop(crop)), to: &state)
        case .delete:
            let selection = state.selection
            return edit("Delete", &state, select: []) { step in
                step.items.removeAll { selection.contains($0.id) }
            }
        case .duplicate:
            let shift = 10 / StepTransform(scale: state.currentStep?.scale).factor
            let copies = state.items.filter { state.selection.contains($0.id) }.map { item in
                Annotation(
                    shape: Geometry.moved(item.shape, by: CGVector(dx: shift, dy: shift)),
                    preset: item.preset,
                    extra: item.extra
                )
            }
            return edit("Duplicate", &state, select: Set(copies.map(\.id))) { step in
                step.items += copies
            }
        case .bringForward:
            let selection = state.selection
            return edit("Bring Forward", &state) { step in
                for _ in 0..<n {
                    step.items.raise(selection)
                }
            }
        case .sendBackward:
            let selection = state.selection
            return edit("Send Backward", &state) { step in
                for _ in 0..<n {
                    step.items.lower(selection)
                }
            }
        case .preset(let preset):
            // A key for a preset the styles file lacks says so, rather than
            // drawing as preset 1 (DECISIONS 2026-10-27).
            guard state.styles.presets[preset] != nil else {
                return [.message("No preset \(preset) in styles")]
            }
            guard !state.selection.isEmpty else {
                state.activePreset = preset
                return []
            }
            let selection = state.selection
            return edit("Change Preset", &state) { step in
                step.items.update(selection) { $0.preset = preset }
            }
        case .setCrop(let rect):
            var crop: CGRect?
            if let rect {
                // Stored pixels: the recorded size, the image's when none is.
                let entry = state.sidecarIndex.map { state.document.sidecar.steps[$0] }
                guard let size = entry?.size ?? state.currentStep?.size,
                    let clamped = Geometry.clampedCrop(rect, to: size)
                else {
                    return readOnly(state) ?? [.message("The crop is outside the image.")]
                }
                crop = clamped
            }
            return edit(rect == nil ? "Remove Crop" : "Crop", &state) { step in
                step.crop = crop
            }
        case .exclude:
            // A toggle, never a deletion (SN-305): the capture stays and a
            // second press brings the step back.
            let excluded = state.currentStep?.excluded ?? false
            let effects = edit(excluded ? "Include Step" : "Exclude Step", &state) { step in
                step.excluded.toggle()
            }
            guard effects == [.sidecarChanged] else {
                return effects
            }
            return effects + [.message(excluded ? "Step included again" : "Step excluded from export")]
        case .removeStep:
            // The file goes first, so the editor changes the case (SN-309).
            if let refused = readOnly(state) {
                return refused
            }
            guard let file = state.currentStep?.file else {
                return []
            }
            if state.document.memoURL != nil, let issue = state.document.memoIssue {
                return [.message("Not removed: \(issue)")]
            }
            return [.removeStep(file)]
        case .restartCounter:
            let effects = edit("Restart Counter", &state) { step in
                step.restartCounter.toggle()
            }
            guard effects == [.sidecarChanged], let index = state.sidecarIndex else {
                return effects
            }
            let restarts = state.document.sidecar.steps[index].restartCounter
            return effects + [.message(restarts ? "Counters restart at 1 on this step" : "Counters continue on this step")]
        case .fill:
            // Filled if any of them is an outline, otherwise all outlines.
            let fillable = state.items.filter { state.selection.contains($0.id) && $0.shape.fill != nil }
            guard !fillable.isEmpty else {
                return []
            }
            let fill = fillable.contains { $0.shape.fill == false }
            let ids = Set(fillable.map(\.id))
            return edit("Change Fill", &state) { step in
                step.items.update(ids) { item in
                    switch item.shape {
                    case .rectangle(let rect, _):
                        item.shape = .rectangle(rect, fill: fill)
                    case .ellipse(let rect, _):
                        item.shape = .ellipse(rect, fill: fill)
                    case .text(let at, let text, _, let leader):
                        item.shape = .text(at: at, text: text, pill: fill, leader: leader)
                    case .highlight(let rect, _):
                        item.shape = .highlight(rect, spotlight: fill)
                    case .blur(let rect, _):
                        item.shape = .blur(rect, pixelate: fill)
                    default:
                        break
                    }
                }
            }
        case .edit:
            guard state.selection.count == 1,
                let item = state.items.first(where: { state.selection.contains($0.id) }),
                case .text = item.shape
            else {
                return []
            }
            if let refused = readOnly(state) {
                return refused
            }
            return [.beginTextEdit(item.id)]
        case .moveStepLater, .moveStepEarlier:
            guard let file = state.currentStep?.file else {
                return []
            }
            let target = command == .moveStepLater ? current + 1 + n : current - n
            return moveStep(file, to: max(0, min(target, last + 1)), in: &state)
        case .moveStep(let file, let target):
            return moveStep(file, to: target, in: &state)
        case .stamp(let target):
            return stamp(onto: target, in: &state)
        case .setCaption(let file, let text):
            return setCaption(text, for: file, in: &state)
        case .undo:
            if let refused = readOnly(state) {
                return refused
            }
            return restore(state.undo.undo(), in: &state)
        case .redo:
            if let refused = readOnly(state) {
                return refused
            }
            return restore(state.undo.redo(), in: &state)
        default:
            break
        }
        return []
    }

    /// Applies `change` to the current step's sidecar entry as one undo
    /// entry; nothing happens, and nothing is recorded, when it changes
    /// nothing.
    private static func edit(
        _ label: String,
        _ state: inout EditorState,
        coalesce: UUID? = nil,
        select: Set<UUID>? = nil,
        _ change: (inout SidecarStep) -> Void
    ) -> [Effect] {
        if let refused = readOnly(state) {
            return refused
        }
        guard let index = state.sidecarIndex else {
            return []
        }
        let before = state.snapshot
        var step = state.document.sidecar.steps[index]
        change(&step)
        step.items.update(Set(step.items.map(\.id))) { $0.shape = StoredPrecision.round($0.shape) }
        step.crop = step.crop.map(StoredPrecision.round)
        guard step != state.document.sidecar.steps[index] else {
            return []
        }
        state.document.sidecar.steps[index] = step
        if let select {
            state.selection = select
        }
        state.undo.record(label, before: before, after: state.snapshot, coalesce: coalesce)
        return [.sidecarChanged]
    }

    /// In the storyboard the frames are the steps: enter opens one, arrows
    /// move between them, zoom sizes them, and tool keys do nothing, since
    /// drawing happens in the single view; step commands still act on the
    /// selected frame. `nil` hands the command to the usual rules.
    private static func storyboard(
        _ command: Command,
        n: Int,
        in state: inout EditorState
    ) -> [Effect]? {
        switch command {
        case .viewStep, .edit:
            state.mode = .step
            state.openedFromStoryboard = command == .edit
            return []
        case .viewStoryboard, .zoomArea, .zoomTo, .tool:
            return []
        case .editCaption:
            return [.beginCaptionEdit]
        case .nudge(let direction, _):
            return Array(repeating: .storyboardMove(direction), count: n)
        default:
            return nil
        }
    }

    /// SN-303: a step moved to `target` among the steps (0 before the
    /// first, the step count after the last), as one undo entry; the step
    /// stays current. Only the sidecar's order changes, so counters follow
    /// and the file names wait for the rename plan.
    private static func moveStep(
        _ file: String,
        to target: Int,
        in state: inout EditorState
    ) -> [Effect] {
        if let refused = readOnly(state) {
            return refused
        }
        let steps = state.document.steps.map(\.file)
        guard let from = steps.firstIndex(of: file), target != from, target != from + 1 else {
            return []
        }
        let before = state.snapshot
        var sidecar = state.document.sidecar.steps
        guard let source = sidecar.firstIndex(where: { $0.file == file }) else {
            return []
        }
        let entry = sidecar.remove(at: source)
        if target < steps.count, let anchor = sidecar.firstIndex(where: { $0.file == steps[target] }) {
            sidecar.insert(entry, at: anchor)
        } else if let lastStep = steps.last(where: { $0 != file }), let anchor = sidecar.firstIndex(where: { $0.file == lastStep }) {
            sidecar.insert(entry, at: anchor + 1)
        } else {
            sidecar.append(entry)
        }
        state.document.sidecar.steps = sidecar
        state.current = state.document.steps.firstIndex { $0.file == file }
        state.undo.record("Move Step", before: before, after: state.snapshot)
        return [.sidecarChanged]
    }

    /// SN-306: the selected blur and highlight regions, or the crop while
    /// cropping, copied onto other steps as one undo entry. Excluded steps
    /// and steps recorded at another size are skipped, since stored pixels
    /// line up only between captures of one size; a region a step already
    /// has is not added twice, and a stamped crop replaces the step's crop.
    /// Counters, arrows, shapes and text are never stamped: a counter would
    /// renumber the story (DECISIONS 2026-10-27).
    private static func stamp(
        onto target: Command.StampTarget,
        in state: inout EditorState
    ) -> [Effect] {
        if let refused = readOnly(state) {
            return refused
        }
        guard let current = state.current, let sourceIndex = state.sidecarIndex else {
            return []
        }
        let source = state.document.sidecar.steps[sourceIndex]
        let cropping = state.tool == .crop
        let regions = state.items.filter { item in
            guard state.selection.contains(item.id) else {
                return false
            }
            switch item.shape {
            case .blur, .highlight:
                return true
            default:
                return false
            }
        }
        if cropping, source.crop == nil {
            return [.message("This step has no crop to stamp")]
        }
        if !cropping, regions.isEmpty {
            return [.message("Select a blur or highlight region to stamp")]
        }
        let count = state.document.steps.count
        let targets: [Int]
        switch target {
        case .next:
            targets = current + 1 < count ? [current + 1] : []
        case .previous:
            targets = current > 0 ? [current - 1] : []
        case .following:
            targets = Array((current + 1)..<max(current + 1, count))
        case .all:
            targets = (0..<count).filter { $0 != current }
        }
        let before = state.snapshot
        var stamped = 0
        var skipped = 0
        for index in targets {
            let step = state.document.steps[index]
            guard !step.excluded,
                let entry = state.document.sidecar.steps.firstIndex(where: { $0.file == step.file }),
                state.document.sidecar.steps[entry].size == source.size
            else {
                skipped += 1
                continue
            }
            if cropping {
                if state.document.sidecar.steps[entry].crop != source.crop {
                    state.document.sidecar.steps[entry].crop = source.crop
                    stamped += 1
                }
                continue
            }
            let existing = state.document.sidecar.steps[entry].items
            let copies = regions
                .filter { region in !existing.contains { $0.shape == region.shape && $0.preset == region.preset } }
                .map { Annotation(shape: $0.shape, preset: $0.preset, extra: $0.extra) }
            if !copies.isEmpty {
                state.document.sidecar.steps[entry].items += copies
                stamped += 1
            }
        }
        let note = skipped > 0 ? " (\(skipped) skipped: excluded or another size)" : ""
        guard stamped > 0 else {
            return [.message(targets.isEmpty ? "No step to stamp onto" : "Nothing new to stamp" + note)]
        }
        state.undo.record("Stamp", before: before, after: state.snapshot)
        let what = cropping ? "the crop" : regions.count == 1 ? "1 region" : "\(regions.count) regions"
        return [.sidecarChanged, .message("Stamped \(what) onto \(stamped) step\(stamped == 1 ? "" : "s")" + note)]
    }

    /// The memo's bullet when the memo references `file`, the sidecar's
    /// `caption` otherwise (DECISIONS 2026-10-27); an empty caption in the
    /// memo is the evidence script's placeholder again.
    private static func setCaption(
        _ text: String,
        for file: String,
        in state: inout EditorState
    ) -> [Effect] {
        if let refused = readOnly(state) {
            return refused
        }
        guard !text.contains(where: \.isNewline) else {
            return [.message("A caption is one line")]
        }
        let caption = text.trimmingCharacters(in: .whitespaces)
        guard caption != state.caption(for: file) else {
            return []
        }
        let before = state.snapshot
        switch state.captionSource(for: file) {
        case .readOnly(let reason):
            return [.message("Captions are read-only: \(reason)")]
        case .memo:
            guard let memo = state.document.memo,
                let data = try? memo.settingCaption(caption.isEmpty ? Memo.placeholder : caption, for: file),
                let updated = try? Memo(data: data)
            else {
                return []
            }
            state.document.memo = updated
            state.undo.record("Caption", before: before, after: state.snapshot)
            return [.memoChanged]
        case .sidecar:
            guard let index = state.document.sidecar.steps.firstIndex(where: { $0.file == file }) else {
                return []
            }
            state.document.sidecar.steps[index].caption = caption.isEmpty ? nil : caption
            state.undo.record("Caption", before: before, after: state.snapshot)
            return [.sidecarChanged]
        }
    }

    private static func readOnly(_ state: EditorState) -> [Effect]? {
        guard let issue = state.document.sidecarIssue else {
            return nil
        }
        return [.message("Read-only: the sidecar cannot be read (\(issue)). Fix or remove it to edit again.")]
    }

    private static func restore(
        _ snapshot: UndoStack.Snapshot?,
        in state: inout EditorState
    ) -> [Effect] {
        guard let snapshot else {
            return []
        }
        state.document.sidecar = snapshot.sidecar
        if let file = snapshot.step, let index = state.document.steps.firstIndex(where: { $0.file == file }) {
            state.current = index
        }
        state.selection = snapshot.selection.intersection(state.items.map(\.id))
        guard snapshot.memo != state.document.memo else {
            return [.sidecarChanged]
        }
        state.document.memo = snapshot.memo
        return [.sidecarChanged, .memoChanged]
    }

    private static func go(to index: Int, in state: inout EditorState) {
        guard index != state.current else {
            return
        }
        state.current = index
        state.selection = []
    }
}

extension Command {
    var isTextEdit: Bool {
        if case .editText = self {
            return true
        }
        return false
    }
}

extension Array where Element == Annotation {
    mutating func update(
        _ ids: Set<UUID>,
        _ body: (inout Annotation) -> Void
    ) {
        for index in indices where ids.contains(self[index].id) {
            body(&self[index])
        }
    }

    /// Each selected item one place towards the top, unless a selected item
    /// is already there.
    mutating func raise(_ ids: Set<UUID>) {
        for index in stride(from: count - 2, through: 0, by: -1)
        where ids.contains(self[index].id) && !ids.contains(self[index + 1].id) {
            swapAt(index, index + 1)
        }
    }

    mutating func lower(_ ids: Set<UUID>) {
        for index in indices.dropFirst()
        where ids.contains(self[index].id) && !ids.contains(self[index - 1].id) {
            swapAt(index, index - 1)
        }
    }
}
