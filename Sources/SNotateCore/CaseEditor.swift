import Foundation

/// What a window holds for an open case: the `EditorState` it shows and the
/// `CaseSession` that keeps the sidecar on disk. Every command goes through
/// `perform`, which runs the pure `Dispatcher` and hands sidecar changes to
/// the session for autosave. When the session reloads from outside, the
/// editor starts again from the new document on the same step, with undo
/// and redo cleared, because history no longer describes the file
/// (DECISIONS 2026-10-26).
@MainActor
public final class CaseEditor {
    public let session: CaseSession
    public private(set) var state: EditorState
    /// After every command and every reload.
    public var onChange: (() -> Void)?
    /// Refusals and dropped changes, for a toast.
    public var onMessage: ((String) -> Void)?
    /// Moves a removed step's capture to the Trash and returns where it
    /// went (SN-309); tests and smoke move it into a folder of their own.
    public var trash: (URL) throws -> URL = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    public init(
        session: CaseSession,
        file: String? = nil
    ) {
        self.session = session
        state = EditorState(document: session.document, file: file)
        session.onReload = { [weak self] in
            self?.reloaded()
        }
        session.onMessage = { [weak self] text in
            self?.onMessage?(text)
        }
    }

    @discardableResult
    public func perform(
        _ command: Command,
        count: Int? = nil
    ) -> [Effect] {
        let effects = Dispatcher.apply(Invocation(command, count: count), to: &state)
        for effect in effects {
            switch effect {
            case .sidecarChanged:
                let sidecar = state.document.sidecar
                session.change { $0 = sidecar }
            case .message(let text):
                onMessage?(text)
            case .memoChanged:
                writeMemo()
            case .removeStep(let file):
                removeStep(file)
            case .restoreStep(let removed):
                restoreStep(removed)
            case .beginTextEdit, .zoom, .pan, .siblingCase, .commandLine, .help, .exportConfig, .setOption, .beginCaptionEdit, .storyboardMove, .listExcluded, .renamePlan, .exportCase, .exportStep, .copyStep:
                break
            }
        }
        onChange?()
        return effects
    }

    /// Takes on what belongs to the window rather than the case, when the
    /// window moves to a sibling case: the tool and its variants, the preset
    /// for new annotations and the styles. Selection and undo stay with
    /// their case.
    public func adopt(from other: EditorState) {
        state.tool = other.tool
        state.filled = other.filled
        state.activePreset = other.activePreset
        state.styles = other.styles
        onChange?()
    }

    /// The styles file changed: the case draws with the new presets at once;
    /// undo is kept, since styles are not part of the case.
    public func setStyles(_ styles: Styles) {
        guard styles != state.styles else {
            return
        }
        state.styles = styles
        onChange?()
    }

    /// A refused write (the memo changed elsewhere) loses this caption and
    /// takes the memo from disk, never overwriting the other edit.
    private func writeMemo() {
        guard let memo = state.document.memo else {
            return
        }
        do {
            try session.writeMemo(memo)
        } catch {
            onMessage?("Caption not saved: \(error); reloaded from disk")
            session.reload()
        }
    }

    /// Moves captions written before the memo existed into it (SN-302); the
    /// window calls it when it shows the case, and a reload runs it again.
    /// Not an undo entry: nothing the author did.
    public func migrateCaptions() {
        guard !session.isReadOnly, let memo = state.document.memo,
            let result = CaptionMigration.migrate(memo: memo, sidecar: state.document.sidecar)
        else {
            return
        }
        if result.memo != memo {
            do {
                try session.writeMemo(result.memo)
            } catch {
                onMessage?("Captions not moved to the memo: \(error)")
                return
            }
            state.document.memo = result.memo
        }
        if result.sidecar != state.document.sidecar {
            let sidecar = result.sidecar
            session.change { $0 = sidecar }
            state.document.sidecar = sidecar
        }
        if !result.kept.isEmpty {
            onMessage?("Kept \(result.kept.count) sidecar caption(s) the memo already has text for: " + result.kept.joined(separator: ", "))
        }
        onChange?()
    }

    /// Applies a confirmed rename plan (SN-303): the waiting change is saved,
    /// the captures renamed, the sidecar's keys follow at once, and the case
    /// reloads from the folder. Renames are file operations, outside undo,
    /// and the history is cleared since it names the old files.
    public func applyRenamePlan(_ plan: RenamePlan) throws(RenamePlan.Failure) {
        session.flush()
        let sidecar = try plan.apply(in: state.document.folder, sidecar: session.document.sidecar)
        session.change { $0 = sidecar }
        session.flush()
        // Swapped names leave the same set of files, which the session's
        // reload cannot tell from no change, so the state is rebuilt here.
        session.reload()
        reloaded()
    }

    /// SN-304: images copied into the case and placed at `gap` among the
    /// steps, the first of them current. A file is added, so this is outside
    /// undo; a wrong insert is removed with `dd`, like any wrong capture.
    @discardableResult
    public func insertSteps(
        _ sources: [InsertStep.Source],
        at gap: Int,
        date: Date = Date()
    ) throws(InsertStep.Failure) -> [String] {
        guard !session.isReadOnly else {
            throw InsertStep.Failure(description: "the sidecar cannot be read, so the case is read-only")
        }
        session.flush()
        let names = try InsertStep.copy(sources, into: state.document.folder, date: date)
        let sidecar = InsertStep.placed(names, at: gap, in: session.document)
        session.change { $0 = sidecar }
        session.flush()
        session.reload()
        reloaded()
        if let first = names.first, let index = state.document.steps.firstIndex(where: { $0.file == first }) {
            perform(.goTo(index + 1))
        }
        return names
    }

    /// SN-309: the capture to the Trash, then its memo blocks and sidecar
    /// entry out of the case, which reloads. A memo that cannot be written
    /// puts the capture back and changes nothing. The removal is kept in
    /// `state.removed` for `cmd-z`, since the reload clears undo.
    private func removeStep(_ file: String) {
        session.flush()
        let document = session.document
        guard let step = document.steps.first(where: { $0.file == file }),
            let entry = document.sidecar.steps.first(where: { $0.file == file })
        else {
            return
        }
        let result = RemoveStep.removing(file, from: document)
        let inTrash: URL
        do {
            inTrash = try trash(step.url)
        } catch {
            onMessage?("Not removed: \(error.localizedDescription)")
            return
        }
        if let memo = result.memo, memo != document.memo {
            do {
                try session.writeMemo(memo)
            } catch {
                try? FileManager.default.moveItem(at: inTrash, to: step.url)
                onMessage?("Not removed: \(error)")
                return
            }
        }
        state.removed.append(
            RemovedStep(
                file: file,
                original: step.url,
                inTrash: inTrash,
                entry: entry,
                after: RemoveStep.anchor(of: file, in: document.sidecar),
                memoBefore: document.memo,
                memoAfter: result.memo
            )
        )
        session.change { $0 = result.sidecar }
        session.flush()
        session.reload()
        reloaded()
        let note = result.kept > 0 ? "; the memo still mentions it in \(result.kept) line\(result.kept == 1 ? "" : "s")" : ""
        onMessage?("Moved \(file) to the Trash; cmd-z puts it back" + note)
    }

    /// Puts the newest removed step back: the capture from the Trash (or
    /// left where Finder's Put Back already took it), the sidecar entry
    /// after the one it followed, and the memo as it was, unless the memo
    /// changed since, which is never overwritten.
    private func restoreStep(_ removed: RemovedStep) {
        session.flush()
        let files = FileManager.default
        state.removed.removeAll { $0 == removed }
        if !files.fileExists(atPath: removed.original.path) {
            do {
                try files.moveItem(at: removed.inTrash, to: removed.original)
            } catch {
                onMessage?("\(removed.file) cannot be put back: it is no longer in the Trash")
                onChange?()
                return
            }
        }
        var note = ""
        if removed.memoBefore != removed.memoAfter, let before = removed.memoBefore {
            if session.document.memo == removed.memoAfter {
                do {
                    try session.writeMemo(before)
                } catch {
                    note = "; the memo block was not put back: \(error)"
                }
            } else {
                note = "; the memo changed since, so its block was not put back"
            }
        }
        session.change { $0 = RemoveStep.restoring(removed, into: $0) }
        session.flush()
        session.reload()
        reloaded()
        if let index = state.document.steps.firstIndex(where: { $0.file == removed.file }) {
            perform(.goTo(index + 1))
        }
        onMessage?("Put \(removed.file) back" + note)
    }

    /// Saves a waiting change; the window calls it when it closes.
    public func close() {
        session.flush()
    }

    /// Says which captures the sidecar lists but the folder lacks (SN-104),
    /// when the case opens; their entries and annotations stay in the
    /// sidecar.
    public func reportMissing() {
        say(missing: state.document.missing)
    }

    private func say(missing: [String]) {
        guard let first = missing.first else {
            return
        }
        onMessage?(
            missing.count == 1
                ? "\(first) is missing; the sidecar keeps it"
                : "\(missing.count) captures are missing; the sidecar keeps them"
        )
    }

    private func reloaded() {
        let file = state.currentStep?.file
        let wasMissing = Set(state.document.missing)
        var fresh = EditorState(document: session.document, file: file)
        if fresh.currentStep?.file != file, let current = state.current, !fresh.document.steps.isEmpty {
            fresh.current = min(current, fresh.document.steps.count - 1)
        }
        // The window's view, tool and preset are not the case's, so a reload
        // from disk keeps them; the case's selection and undo start again.
        fresh.activePreset = state.activePreset
        fresh.styles = state.styles
        fresh.tool = state.tool
        fresh.filled = state.filled
        fresh.mode = state.mode
        fresh.openedFromStoryboard = state.openedFromStoryboard
        fresh.removed = state.removed
        state = fresh
        migrateCaptions()
        say(missing: state.document.missing.filter { !wasMissing.contains($0) })
        if session.droppedLocalChange {
            onMessage?("Reloaded from disk; the last change was not saved.")
        }
        onChange?()
    }
}
