import AppKit
import UniformTypeIdentifiers
import SNotateCore

/// One case per window (SN-601): the canvas or the storyboard for its
/// `CaseEditor` (SN-301), or a prompt to open one. `]` and `[` swap in a
/// sibling case (SN-501). Closing the window or leaving a case saves a
/// waiting change.
final class ContentView: NSView {
    override var isFlipped: Bool { true }
}

final class CaseWindowController: NSWindowController, NSWindowDelegate {
    private(set) var editor: CaseEditor?
    let canvas = CanvasView()
    let storyboardView = StoryboardView()
    private let scroll = NSScrollView()
    private let content = ContentView()
    private var shownMode: ViewMode?
    /// The config's export folder and, later, options (SN-401, SN-403).
    private var config = SNotateConfig()
    private var exporting = false
    private let toast = ToastView()
    private let prompt = CommandPromptView()
    private let help = HelpOverlayView()
    /// The keymap the overlay shows.
    private var keymap = DefaultKeymap.keymap
    var onClose: (() -> Void)?
    /// Asks the app for the case this many siblings away.
    var onSiblingCase: ((Int) -> Void)? {
        didSet {
            canvas.onSiblingCase = onSiblingCase
        }
    }

    init(editor: CaseEditor?) {
        self.editor = editor
        let size = TestHooks.windowSize ?? CGSize(width: 1100, height: 720)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = CGSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        content.frame = NSRect(origin: .zero, size: size)
        window.contentView = content
        super.init(window: window)
        window.delegate = self
        for view in [canvas, scroll] as [NSView] {
            view.frame = content.bounds
            view.autoresizingMask = [.width, .height]
            content.addSubview(view)
        }
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = storyboardView
        storyboardView.autoresizingMask = [.width]
        scroll.isHidden = true
        storyboardView.perform = { [weak self] command in
            self?.canvas.perform(command)
        }
        storyboardView.onInsert = { [weak self] sources, gap in
            self?.insert(sources, at: gap)
        }
        storyboardView.forwardKey = { [weak self] event in
            self?.canvas.keyDown(with: event)
        }
        canvas.onStoryboard = { [weak self] effect in
            self?.storyboardView.handle(effect)
        }
        prompt.translatesAutoresizingMaskIntoConstraints = false
        prompt.isHidden = true
        content.addSubview(prompt)
        NSLayoutConstraint.activate([
            prompt.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            prompt.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            prompt.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        prompt.onSubmit = { [weak self] text in
            self?.submitPrompt(text)
        }
        prompt.onCancel = { [weak self] in
            self?.endPrompt()
        }
        canvas.onCommandLine = { [weak self] in
            self?.beginPrompt()
        }
        canvas.onHelp = { [weak self] in
            self?.toggleHelp()
        }
        help.isHidden = true
        help.autoresizingMask = [.width, .height]
        help.onClose = { [weak self] in
            self?.closeHelp()
        }
        content.addSubview(help)
        storyboardView.canvas = canvas
        canvas.onListExcluded = { [weak self] files in
            self?.listExcluded(files)
        }
        canvas.onExport = { [weak self] effect in
            self?.export(effect)
        }
        canvas.onRenamePlan = { [weak self] in
            self?.showRenamePlan()
        }
        attach(editor)
        window.center()
    }

    private func beginPrompt() {
        canvas.endEditing()
        storyboardView.endCaptionEdit(commit: true)
        prompt.begin()
    }

    private func endPrompt() {
        prompt.end()
        window?.makeFirstResponder(activeView)
    }

    private var activeView: NSView {
        editor?.state.mode == .storyboard ? storyboardView : canvas
    }

    /// A step number or a command; a mistake is said in a toast.
    private func submitPrompt(_ text: String) {
        endPrompt()
        do {
            canvas.perform(try Command.parseCommandLine(text))
        } catch {
            show(message: "\(error)")
        }
    }

    /// Leaves the current case, saved, for `editor`, keeping the window's
    /// tool, preset and zoom.
    func replace(with editor: CaseEditor) {
        canvas.endEditing()
        storyboardView.endCaptionEdit(commit: true)
        canvas.gesture = nil
        if let old = self.editor {
            editor.adopt(from: old.state)
            old.onChange = nil
            old.onMessage = nil
            old.close()
        }
        self.editor = editor
        attach(editor)
    }

    /// New config and keymap: a key sequence typed halfway is dropped.
    func apply(_ settings: Settings) {
        canvas.keyTimeout?.cancel()
        canvas.matcher = KeyMatcher(keymap: settings.keymap)
        keymap = settings.keymap
        if !help.isHidden {
            help.sections = KeyHelp.sections(keymap: keymap)
        }
        canvas.snap = settings.config.snap
        config = settings.config
        editor?.setStyles(settings.styles)
    }

    /// `:rename-plan` (SN-303): every rename, what is left alone and why,
    /// and what blocks the plan, in a sheet; the files are renamed only from
    /// its button, never silently.
    private func showRenamePlan() {
        guard let editor, let window else {
            return
        }
        canvas.endEditing()
        storyboardView.endCaptionEdit(commit: true)
        let plan = RenamePlan(document: editor.state.document)
        guard !plan.renames.isEmpty || !plan.blocked.isEmpty else {
            let note = plan.outOfOrder.isEmpty ? "" : "; out of order with the memo: " + plan.outOfOrder.joined(separator: ", ")
            show(message: "File names already follow the story order" + note)
            return
        }
        var lines = plan.renames.map { "\($0.from)  ->  \($0.to)" }
        if !plan.kept.isEmpty {
            lines += ["", "Left alone:"] + plan.kept.map { "  \($0.file): \($0.reason)" }
        }
        if !plan.outOfOrder.isEmpty {
            lines += ["", "Out of order with the memo (move its blocks by hand):"] + plan.outOfOrder.map { "  " + $0 }
        }
        if !plan.blocked.isEmpty {
            lines += ["", "Cannot rename:"] + plan.blocked.map { "  " + $0 }
        }
        if TestHooks.confirmsSheets {
            FileHandle.standardError.write(Data(lines.map { "rename-plan: " + $0 + "\n" }.joined().utf8))
            if plan.canApply {
                applyRenamePlan(plan)
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = plan.canApply ? "Rename \(plan.renames.count) captures to follow the story order?" : "The rename plan cannot be applied"
        alert.informativeText = plan.canApply
            ? "The memo and the evidence script go by these names. Renaming cannot be undone with cmd-z."
            : "Fix what is listed under Cannot rename, then ask again."
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 220))
        text.string = lines.joined(separator: "\n")
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.isEditable = false
        let scroll = NSScrollView(frame: text.frame)
        scroll.hasVerticalScroller = true
        scroll.documentView = text
        alert.accessoryView = scroll
        if plan.canApply {
            alert.addButton(withTitle: "Rename \(plan.renames.count) Files")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.addButton(withTitle: "OK")
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            if plan.canApply, response == .alertFirstButtonReturn {
                self?.applyRenamePlan(plan)
            }
        }
    }

    private func applyRenamePlan(_ plan: RenamePlan) {
        do {
            try editor?.applyRenamePlan(plan)
            canvas.clearImageCaches()
            storyboardView.clearThumbnails()
            show(message: "Renamed \(plan.renames.count) captures; undo history cleared")
        } catch {
            show(message: "Rename stopped: \(error)")
        }
    }

    /// SN-401, SN-402: the case or one step into `notated/`, or one step's
    /// bytes on the clipboard, rendered off the main thread from the case as
    /// it is now, a waiting change saved first; the result is a toast.
    private func export(_ effect: Effect) {
        guard let editor, !exporting else {
            return
        }
        canvas.endEditing()
        storyboardView.endCaptionEdit(commit: true)
        editor.session.flush()
        let document = editor.state.document
        let styles = editor.state.styles
        let folder = config.notatedDir
        let options = ExportOptions(config: config)
        exporting = true
        Task.detached { [weak self] in
            let outcome: Result<ExportOutcome, ExportError>
            do throws(ExportError) {
                switch effect {
                case .exportStep(let file):
                    outcome = .success(.report(try Exporter.exportStep(file, of: document, styles: styles, folderName: folder, options: options)))
                case .copyStep(let file):
                    outcome = .success(.copy(try Exporter.exportedData(for: file, of: document, styles: styles, options: options), file))
                default:
                    outcome = .success(.report(try Exporter.exportCase(document, styles: styles, folderName: folder, options: options)))
                }
            } catch {
                outcome = .failure(error)
            }
            MainQueue.async {
                guard let self else {
                    return
                }
                self.exporting = false
                switch outcome {
                case .success(.report(let report)):
                    self.show(message: "Exported to \(folder)/: " + report.summary)
                case .success(.copy(let data, let file)):
                    let pasteboard = TestHooks.pasteboard
                    pasteboard.clearContents()
                    pasteboard.setData(data, forType: options.format == .png ? .png : NSPasteboard.PasteboardType(UTType.jpeg.identifier))
                    self.show(message: "Copied \(file) as exported")
                case .failure(let error):
                    self.show(message: "Not exported: \(error)")
                }
            }
        }
    }

    private enum ExportOutcome: Sendable {
        case report(ExportReport)
        /// The export's bytes, in the config's format, for the clipboard.
        case copy(Data, String)
    }

    /// Every menu item that is a command comes here (SN-505), and goes the
    /// way keys and the `:` line go; without a case only help and exporting
    /// the config do anything.
    @objc func performMenuCommand(_ sender: Any?) {
        guard let command = ((sender as? NSMenuItem)?.representedObject as? MenuCommand)?.command else {
            return
        }
        guard editor != nil else {
            switch command {
            case .help:
                toggleHelp()
            case .exportConfig(let path):
                canvas.onExportConfig?(path)
            default:
                break
            }
            return
        }
        canvas.perform(command)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performMenuCommand(_:)),
            let command = (menuItem.representedObject as? MenuCommand)?.command
        else {
            return true
        }
        let state = editor?.state
        let checked: Bool
        switch command {
        case .tool(let tool):
            checked = state?.tool == tool
        case .preset(let n):
            checked = state?.activePreset == n
        case .viewStep:
            checked = state?.mode == .step
        case .viewStoryboard:
            checked = state?.mode == .storyboard
        case .help:
            checked = !help.isHidden
        default:
            checked = false
        }
        menuItem.state = checked ? .on : .off
        return Dispatcher.isAvailable(command, in: state)
    }

    /// `?` (SN-503): the live keymap over the window, and back.
    func toggleHelp() {
        if help.isHidden {
            help.sections = KeyHelp.sections(keymap: keymap)
            help.frame = content.bounds
            help.isHidden = false
            window?.makeFirstResponder(help)
            TestHooks.say("help", "shown, \(help.sections.count) sections")
        } else {
            closeHelp()
        }
    }

    private func closeHelp() {
        TestHooks.say("help", "closed")
        help.isHidden = true
        window?.makeFirstResponder(editor?.state.mode == .storyboard ? storyboardView : canvas)
    }

    private func insert(_ sources: [InsertStep.Source], at gap: Int) {
        do {
            let names = try editor?.insertSteps(sources, at: gap) ?? []
            let what = names.count == 1 ? names[0] : "\(names.count) steps"
            show(message: "Inserted \(what); x excludes a wrong one")
        } catch {
            show(message: "Not inserted: \(error)")
        }
    }

    /// The excluded captures, one per line on the clipboard, ready to paste
    /// after `rm` in the case folder before the rename script runs.
    private func listExcluded(_ files: [String]) {
        guard !files.isEmpty else {
            show(message: "No excluded steps")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(files.joined(separator: "\n") + "\n", forType: .string)
        show(message: "Copied \(files.count) excluded: " + files.joined(separator: ", "))
    }

    func show(message: String) {
        TestHooks.say("toast", message)
        toast.show(message, in: content)
    }

    private func attach(_ editor: CaseEditor?) {
        canvas.editor = editor
        storyboardView.editor = editor
        editor?.onChange = { [weak self] in
            self?.refresh()
        }
        editor?.onMessage = { [weak self] text in
            self?.show(message: text)
        }
        if let trash = TestHooks.trash {
            editor?.trash = trash
        }
        refresh()
        editor?.migrateCaptions()
        editor?.reportMissing()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    var isEmpty: Bool { editor == nil }

    /// The view the mode asks for; focus moves only when the mode changes,
    /// so a field being typed in keeps it.
    func refresh() {
        if window?.title != title {
            TestHooks.say("title", title)
        }
        window?.title = title
        let mode = editor?.state.mode ?? .step
        if mode != shownMode {
            shownMode = mode
            if mode == .storyboard {
                TestHooks.startTiming(["storyboard first paint", "storyboard visible frames"])
            }
            canvas.endEditing()
            storyboardView.endCaptionEdit(commit: true)
            scroll.isHidden = mode != .storyboard
            canvas.isHidden = mode == .storyboard
            window?.makeFirstResponder(activeView)
        }
        if mode == .storyboard {
            storyboardView.relayout()
        }
        canvas.needsDisplay = true
    }

    /// `<case-id>  step i/N  file`, as SN-601 asks.
    var title: String {
        guard let editor else {
            return "sNotate"
        }
        let state = editor.state
        guard let current = state.current, let step = state.currentStep else {
            return state.document.caseID
        }
        var title = "\(state.document.caseID)  step \(current + 1)/\(state.document.steps.count)  \(step.file)"
        if step.excluded {
            title += "  (excluded)"
        }
        if editor.session.isReadOnly {
            title += "  (read-only)"
        }
        return title
    }

    func windowWillClose(_ notification: Notification) {
        canvas.endEditing()
        storyboardView.endCaptionEdit(commit: true)
        editor?.close()
        onClose?()
    }
}
