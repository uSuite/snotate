import AppKit
import SNotateCore

/// All steps of the case as frames in reading order (SN-301), each with its
/// number, file name and caption, the current step outlined in the accent.
/// A frame is the step as it will be exported, rendered off the main thread
/// and cached, so the grid is on screen at once with grey placeholders that
/// fill in. Keys go through the canvas's keymap; the Dispatcher's
/// storyboard rules make enter open a step and `i` edit its caption, which
/// is written to the memo one line at a time (SN-302).
final class StoryboardView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    var editor: CaseEditor? {
        didSet {
            relayout()
        }
    }

    /// Runs a command the way the canvas does, effects included.
    var perform: ((Command) -> Void)?
    /// Hands key presses to the canvas's keymap matcher.
    var forwardKey: ((NSEvent) -> Void)?
    /// Images dropped or pasted, and the gap among the steps they go to
    /// (SN-304).
    var onInsert: (([InsertStep.Source], Int) -> Void)?
    /// Where files dragged in from outside would land.
    private var dropGap: Int?

    static let margin: CGFloat = 24
    static let gap: CGFloat = 24
    /// Frame widths in points, from thumbnails to readable.
    static let widths: ClosedRange<CGFloat> = 160...960
    static let defaultWidth: CGFloat = 320
    /// The file name and caption lines under a thumbnail.
    static let textHeight: CGFloat = 46

    private(set) var frameWidth = StoryboardView.defaultWidth
    private var thumbnails: [String: (key: ThumbnailKey, image: CGImage)] = [:]
    private var rendering: Set<ThumbnailKey> = []
    private var captionField: NSTextField?
    private var captionFile: String?
    /// A frame being dragged to a new place in the story (SN-303): where
    /// the press was and the gap it would land in.
    private var drag: (file: String, start: CGPoint, gap: Int?)?

    /// Everything a frame's picture depends on.
    private struct ThumbnailKey: Hashable, Sendable {
        let url: URL
        let items: [Annotation]
        let numbers: [Int]
        let crop: CGRect?
        let scale: StepScale?
        let styles: Styles
        let pixels: Int

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.url == rhs.url && lhs.items == rhs.items && lhs.numbers == rhs.numbers && lhs.crop == rhs.crop
                && lhs.scale == rhs.scale && lhs.styles == rhs.styles && lhs.pixels == rhs.pixels
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(url)
            hasher.combine(pixels)
            hasher.combine(items.count)
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var thumbnailHeight: CGFloat {
        (frameWidth * 0.625).rounded()
    }

    private var cellHeight: CGFloat {
        thumbnailHeight + Self.textHeight
    }

    var columns: Int {
        max(1, Int((bounds.width - 2 * Self.margin + Self.gap) / (frameWidth + Self.gap)))
    }

    private var count: Int {
        editor?.state.document.steps.count ?? 0
    }

    func cell(_ index: Int) -> CGRect {
        let column = index % columns
        let row = index / columns
        return CGRect(
            x: Self.margin + CGFloat(column) * (frameWidth + Self.gap),
            y: Self.margin + CGFloat(row) * (cellHeight + Self.gap),
            width: frameWidth,
            height: cellHeight
        )
    }

    private func thumbnailBox(_ index: Int) -> CGRect {
        let cell = cell(index)
        return CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: thumbnailHeight)
    }

    private func captionBox(_ index: Int) -> CGRect {
        let cell = cell(index)
        return CGRect(x: cell.minX, y: cell.maxY - 24, width: cell.width, height: 22)
    }

    private func height(forWidth width: CGFloat) -> CGFloat {
        let columns = max(1, Int((width - 2 * Self.margin + Self.gap) / (frameWidth + Self.gap)))
        let rows = (count + columns - 1) / columns
        return 2 * Self.margin + CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * Self.gap
    }

    /// The document view keeps the clip view's width and grows to its rows.
    override func setFrameSize(_ newSize: NSSize) {
        let visible = enclosingScrollView?.contentSize.height ?? newSize.height
        super.setFrameSize(NSSize(width: newSize.width, height: max(visible, height(forWidth: newSize.width))))
        placeCaptionField()
    }

    func relayout() {
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        setFrameSize(NSSize(width: width, height: bounds.height))
        if let current = editor?.state.current, current < count {
            scrollToVisible(cell(current).insetBy(dx: -Self.margin / 2, dy: -Self.margin / 2))
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Brand.canvas.setFill()
        dirtyRect.fill()
        guard let state = editor?.state else {
            return
        }
        let numbers = state.document.counterNumbers
        for (index, step) in state.document.steps.enumerated() where cell(index).intersects(dirtyRect) {
            drawFrame(index, step: step, state: state, numbers: numbers)
        }
        if let gap = drag?.gap ?? dropGap {
            Brand.accent.setFill()
            gapBar(gap).fill()
        }
        if let editor, Self.orderDiffers(editor.state.document) {
            draw(
                "Story order differs from the file names; :rename-plan shows the renames",
                in: CGRect(x: Self.margin, y: 4, width: bounds.width - 2 * Self.margin, height: 16),
                size: 11,
                color: Brand.accent
            )
        }
        TestHooks.endTiming("storyboard first paint")
    }

    private func drawFrame(
        _ index: Int,
        step: CaseStep,
        state: EditorState,
        numbers: [UUID: Int]
    ) {
        let box = thumbnailBox(index)
        let picture: NSRect
        if let image = thumbnail(for: step, state: state, numbers: numbers) {
            let aspect = CGFloat(image.height) / CGFloat(max(1, image.width))
            let size = aspect * box.width <= box.height
                ? CGSize(width: box.width, height: box.width * aspect)
                : CGSize(width: box.height / aspect, height: box.height)
            picture = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
            NSImage(cgImage: image, size: size).draw(
                in: picture,
                from: .zero,
                operation: .sourceOver,
                fraction: step.excluded ? 0.35 : 1,
                respectFlipped: true,
                hints: nil
            )
        } else {
            picture = box
            NSColor(white: 0.2, alpha: 1).setFill()
            box.fill()
        }
        if index == state.current {
            Brand.accent.setStroke()
            let outline = NSBezierPath(rect: picture.insetBy(dx: -3, dy: -3))
            outline.lineWidth = 3
            outline.stroke()
        }
        let cell = cell(index)
        var header = "\(index + 1)  \(step.file)"
        if step.excluded {
            header += "  excluded"
        }
        draw(header, in: CGRect(x: cell.minX, y: box.maxY + 6, width: cell.width, height: 16), size: 11, color: .secondaryLabelColor)
        guard captionFile != step.file else {
            return
        }
        let caption = state.caption(for: step.file)
        draw(
            caption.isEmpty ? "No caption" : caption,
            in: captionBox(index),
            size: 13,
            color: caption.isEmpty ? .tertiaryLabelColor : .labelColor
        )
    }

    private func draw(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: color,
                .paragraphStyle: style,
            ]
        )
    }

    /// The cached picture, rendering a fresh one in the background when the
    /// step changed; the last one stays on screen until then.
    private func thumbnail(
        for step: CaseStep,
        state: EditorState,
        numbers: [UUID: Int]
    ) -> CGImage? {
        guard let entry = state.document.sidecar.steps.first(where: { $0.file == step.file }) else {
            return nil
        }
        let key = ThumbnailKey(
            url: step.url,
            items: entry.items,
            numbers: entry.items.compactMap { numbers[$0.id] },
            crop: entry.crop,
            scale: step.scale,
            styles: state.styles,
            pixels: Int(frameWidth * (window?.backingScaleFactor ?? 2))
        )
        let cached = thumbnails[step.file]
        if cached?.key != key, !rendering.contains(key) {
            rendering.insert(key)
            let file = step.file
            let items = entry.items
            Task.detached(priority: .userInitiated) { [weak self] in
                let image = Renderer.loadImage(at: key.url).map { capture in
                    Renderer.thumbnail(
                        Scene(
                            image: capture,
                            items: items,
                            numbers: numbers,
                            transform: StepTransform(scale: key.scale),
                            styles: key.styles
                        ),
                        crop: key.crop,
                        width: key.pixels
                    )
                }
                MainQueue.async {
                    guard let self else {
                        return
                    }
                    self.rendering.remove(key)
                    if let image {
                        self.thumbnails[file] = (key, image)
                        self.needsDisplay = true
                    }
                    if self.rendering.isEmpty {
                        TestHooks.endTiming("storyboard visible frames")
                    }
                }
            }
        }
        return cached?.image
    }

    override func keyDown(with event: NSEvent) {
        forwardKey?(event)
    }

    override func mouseDown(with event: NSEvent) {
        endCaptionEdit(commit: true)
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let index = (0..<count).first(where: { cell($0).contains(point) }),
            let file = editor?.state.document.steps[index].file
        else {
            return
        }
        perform?(.goTo(index + 1))
        if event.clickCount == 2 {
            perform?(captionBox(index).contains(point) ? .editCaption : .edit)
            return
        }
        drag = (file, point, nil)
    }

    /// Past a few points a press becomes a drag; the amber bar shows the
    /// gap the frame would land in.
    override func mouseDragged(with event: NSEvent) {
        guard let current = drag else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard current.gap != nil || hypot(point.x - current.start.x, point.y - current.start.y) >= 4 else {
            return
        }
        drag?.gap = gap(at: point)
        autoscroll(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = drag else {
            return
        }
        drag = nil
        needsDisplay = true
        if let gap = current.gap {
            perform?(.moveStep(current.file, to: gap))
        }
    }

    /// The place among the steps nearest `point`: 0 before the first frame,
    /// the step count after the last.
    func gap(at point: CGPoint) -> Int {
        let rowHeight = cellHeight + Self.gap
        let row = max(0, Int((point.y - Self.margin + Self.gap / 2) / rowHeight))
        let column = Int(((point.x - Self.margin) / (frameWidth + Self.gap)).rounded())
        return min(max(0, row * columns + min(max(0, column), columns)), count)
    }

    private func gapBar(_ gap: Int) -> CGRect {
        let atEnd = gap > 0 && (gap == count || gap % columns == 0)
        let anchor = cell(atEnd ? gap - 1 : gap)
        let x = atEnd ? anchor.maxX + Self.gap / 2 : anchor.minX - Self.gap / 2
        return CGRect(x: x - 2, y: anchor.minY, width: 4, height: thumbnailHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    /// Image files from Finder or sView, or image data, as insert sources.
    static func sources(from pasteboard: NSPasteboard) -> [InsertStep.Source] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls.map(InsertStep.Source.file)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) {
                return [.data(data)]
            }
        }
        return []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard editor != nil, !Self.sources(from: sender.draggingPasteboard).isEmpty else {
            return []
        }
        dropGap = gap(at: convert(sender.draggingLocation, from: nil))
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropGap = nil
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let gap = dropGap ?? gap(at: convert(sender.draggingLocation, from: nil))
        dropGap = nil
        needsDisplay = true
        let sources = Self.sources(from: sender.draggingPasteboard)
        guard !sources.isEmpty else {
            return false
        }
        onInsert?(sources, gap)
        return true
    }

    /// cmd-v: images on the clipboard go after the selected frame.
    @objc func paste(_ sender: Any?) {
        let sources = Self.sources(from: TestHooks.pasteboard)
        guard !sources.isEmpty else {
            return
        }
        onInsert?(sources, (editor?.state.current ?? -1) + 1)
    }

    /// The canvas, which performs undo, redo, delete and select all for
    /// the storyboard too (SN-505).
    weak var canvas: CanvasView?

    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if let canvas, canvas.responds(to: action) {
            return canvas
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)) {
            return editor != nil && !Self.sources(from: TestHooks.pasteboard).isEmpty
        }
        return true
    }

    /// A drop for the test hook, without a drag session.
    func drop(_ urls: [URL], at point: CGPoint) {
        onInsert?(urls.map(InsertStep.Source.file), gap(at: point))
    }

    /// Whether the rename plan has anything to say: the banner's test.
    static func orderDiffers(_ document: CaseDocument) -> Bool {
        let plan = RenamePlan(document: document)
        return !plan.renames.isEmpty || !plan.outOfOrder.isEmpty
    }

    /// Captures renamed under the same names: the cached pictures are stale.
    func clearThumbnails() {
        thumbnails = [:]
        needsDisplay = true
    }

    /// Effects the Dispatcher leaves to the storyboard.
    func handle(_ effect: Effect) {
        guard let state = editor?.state, let current = state.current else {
            return
        }
        switch effect {
        case .storyboardMove(let direction):
            let offset: Int
            switch direction {
            case .left:
                offset = -1
            case .right:
                offset = 1
            case .up:
                offset = -columns
            case .down:
                offset = columns
            }
            let target = current + offset
            if (0..<count).contains(target) {
                perform?(.goTo(target + 1))
            }
        case .zoom(let request):
            switch request {
            case .steps(let n):
                frameWidth = min(max(frameWidth * pow(Viewport.step, CGFloat(n)), Self.widths.lowerBound), Self.widths.upperBound).rounded()
            case .fit, .actual:
                frameWidth = Self.defaultWidth
            case .area, .inAt:
                return
            }
            relayout()
        case .beginCaptionEdit:
            beginCaptionEdit()
        default:
            break
        }
    }

    private func beginCaptionEdit() {
        guard let state = editor?.state, let index = state.current, let step = state.currentStep else {
            return
        }
        endCaptionEdit(commit: true)
        if case .readOnly(let reason) = state.captionSource(for: step.file) {
            editor?.onMessage?("Captions are read-only: \(reason)")
            return
        }
        scrollToVisible(cell(index))
        let field = NSTextField(string: state.caption(for: step.file))
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderString = "Caption for \(step.file)"
        addSubview(field)
        captionField = field
        captionFile = step.file
        placeCaptionField()
        window?.makeFirstResponder(field)
        field.currentEditor()?.moveToEndOfDocument(nil)
        needsDisplay = true
    }

    private func placeCaptionField() {
        guard let field = captionField, let file = captionFile,
            let index = editor?.state.document.steps.firstIndex(where: { $0.file == file })
        else {
            return
        }
        field.frame = captionBox(index).insetBy(dx: -4, dy: -2)
    }

    /// Commits or drops the caption being typed; one undo entry either way.
    func endCaptionEdit(commit: Bool) {
        guard let field = captionField, let file = captionFile else {
            return
        }
        let text = field.stringValue
        captionField = nil
        captionFile = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        if commit {
            perform?(.setCaption(file, text))
        }
        needsDisplay = true
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy selector: Selector
    ) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            endCaptionEdit(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endCaptionEdit(commit: false)
            return true
        default:
            return false
        }
    }

    /// Focus leaving the field keeps what was typed.
    func controlTextDidEndEditing(_ notification: Notification) {
        if captionField != nil {
            endCaptionEdit(commit: true)
        }
    }
}
