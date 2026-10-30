import Foundation

/// A step taken out of the case with `dd` (SN-309), with what it takes to
/// put it back: where the capture went in the Trash, its sidecar entry and
/// the entry it followed, and the memo before and after its block left.
public struct RemovedStep: Sendable, Equatable {
    public let file: String
    public let original: URL
    public let inTrash: URL
    public let entry: SidecarStep
    /// The sidecar entry it followed, `nil` when it was first.
    public let after: String?
    public let memoBefore: Memo?
    public let memoAfter: Memo?
}

/// SN-309: the pure part of removing a step. The capture goes to the Trash,
/// never deleted, so the editor can put it back on `cmd-z` (DECISIONS
/// 2026-10-29); its sidecar entry and memo blocks go with it.
public enum RemoveStep {
    /// The sidecar without `file`'s entry and the memo without its blocks;
    /// `kept` counts references the memo shares a line with other text.
    public static func removing(
        _ file: String,
        from document: CaseDocument
    ) -> (sidecar: Sidecar, memo: Memo?, kept: Int) {
        var sidecar = document.sidecar
        sidecar.steps.removeAll { $0.file == file }
        guard let result = document.memo?.removingReferences(to: file) else {
            return (sidecar, document.memo, 0)
        }
        return (sidecar, result.memo, result.kept)
    }

    /// The entry `file` follows in the sidecar, `nil` when it is first.
    static func anchor(
        of file: String,
        in sidecar: Sidecar
    ) -> String? {
        guard let index = sidecar.steps.firstIndex(where: { $0.file == file }), index > 0 else {
            return nil
        }
        return sidecar.steps[index - 1].file
    }

    /// `removed`'s entry back after the one it followed, or first when that
    /// one is gone too; unchanged when the sidecar has the file again.
    public static func restoring(
        _ removed: RemovedStep,
        into sidecar: Sidecar
    ) -> Sidecar {
        guard !sidecar.steps.contains(where: { $0.file == removed.file }) else {
            return sidecar
        }
        var restored = sidecar
        let index = removed.after.flatMap { anchor in sidecar.steps.firstIndex { $0.file == anchor } }.map { $0 + 1 } ?? 0
        restored.steps.insert(removed.entry, at: index)
        return restored
    }
}
