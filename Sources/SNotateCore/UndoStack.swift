import Foundation

/// Case-wide undo (SN-105): one entry per Command, holding the sidecar,
/// memo, current step and selection before and after it (DECISIONS
/// 2026-10-26, the memo since 2026-10-27, so caption edits undo too).
/// Snapshots instead of inverse operations, so undo can never drift from
/// what a command did; the sidecar shares storage between snapshots, so
/// unlimited history within a session stays cheap. Typing into one text
/// annotation updates the top entry until coalescing ends.
public struct UndoStack: Sendable, Equatable {
    public struct Snapshot: Sendable, Equatable {
        public let sidecar: Sidecar
        public let memo: Memo?
        /// The current step's file, so a reload that shifts indices still
        /// finds it.
        public let step: String?
        public let selection: Set<UUID>

        public init(
            sidecar: Sidecar,
            memo: Memo? = nil,
            step: String?,
            selection: Set<UUID>
        ) {
            self.sidecar = sidecar
            self.memo = memo
            self.step = step
            self.selection = selection
        }
    }

    struct Entry: Sendable, Equatable {
        let label: String
        let before: Snapshot
        var after: Snapshot
        let coalesce: UUID?
    }

    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []
    /// The text annotation whose edits still merge into the top entry.
    private var open: UUID?

    public init() {}

    public var count: Int { undoEntries.count }
    public var undoLabel: String? { undoEntries.last?.label }
    public var redoLabel: String? { redoEntries.last?.label }

    public mutating func record(
        _ label: String,
        before: Snapshot,
        after: Snapshot,
        coalesce: UUID? = nil
    ) {
        redoEntries.removeAll()
        if let coalesce, coalesce == open, undoEntries.last?.coalesce == coalesce {
            undoEntries[undoEntries.count - 1].after = after
            return
        }
        undoEntries.append(Entry(label: label, before: before, after: after, coalesce: coalesce))
        open = coalesce
    }

    public mutating func endCoalescing() {
        open = nil
    }

    /// The state to go back to, `nil` when there is nothing to undo.
    public mutating func undo() -> Snapshot? {
        open = nil
        guard let entry = undoEntries.popLast() else {
            return nil
        }
        redoEntries.append(entry)
        return entry.before
    }

    public mutating func redo() -> Snapshot? {
        open = nil
        guard let entry = redoEntries.popLast() else {
            return nil
        }
        undoEntries.append(entry)
        return entry.after
    }

    /// After an outside reload, history no longer describes the file.
    public mutating func clear() {
        undoEntries.removeAll()
        redoEntries.removeAll()
        open = nil
    }
}
