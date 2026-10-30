import Foundation

/// An open case kept in step with its folder (SN-103): changes are saved to
/// the sidecar after a short pause with no dialog, and outside changes to the
/// folder, the sidecar or the memo (another editor, git checkout, a new
/// capture) are reloaded. When the sidecar on disk cannot be read the session is read-only
/// and never saves over it, until the file parses again.
///
/// A change still waiting to be saved when the sidecar changes outside is
/// saved first if the file is as we left it; otherwise the outside version
/// wins and `droppedLocalChange` is set, since a checkout or a merge is the
/// likelier truth than half a second of editing.
@MainActor
public final class CaseSession {
    public private(set) var document: CaseDocument
    /// Called after the document changed because of the disk.
    public var onReload: (() -> Void)?
    public private(set) var droppedLocalChange = false
    public private(set) var saveError: String?
    /// What the window is told about the disk (SN-605): a save that failed,
    /// one that works again, the case folder gone. Each is said when it
    /// starts, not on every attempt.
    public var onMessage: ((String) -> Void)?

    private let saveDelay: Duration
    private var dirty = false
    private var pendingSave: Task<Void, Never>?
    /// The sidecar bytes as last read or written by this session.
    private var lastSeen: Data?
    private var watchers: [DirectoryWatcher] = []
    private var folderGone = false

    public init(
        document: CaseDocument,
        saveDelay: Duration = .milliseconds(300),
        watchDebounce: DispatchTimeInterval = .milliseconds(200)
    ) {
        self.document = document
        self.saveDelay = saveDelay
        lastSeen = document.loadedBytes
        let named = [
            document.sidecarURL.lastPathComponent,
            document.caseID + ".md",
        ]
        let folders = [
            document.folder,
            document.folder.appendingPathComponent(CaseDocument.assetsFolder, isDirectory: true),
        ]
        watchers = folders.compactMap { folder in
            DirectoryWatcher(
                url: folder,
                files: folder == document.folder ? named : [],
                debounce: watchDebounce
            ) { [weak self] in
                MainActor.assumeIsolated {
                    self?.diskChanged()
                }
            }
        }
    }

    public var isReadOnly: Bool { document.sidecarIssue != nil }

    /// Applies `body` to the sidecar and schedules a save; `false` when the
    /// case is read-only and nothing changed.
    @discardableResult
    public func change(_ body: (inout Sidecar) -> Void) -> Bool {
        guard !isReadOnly else {
            return false
        }
        var sidecar = document.sidecar
        body(&sidecar)
        guard sidecar != document.sidecar else {
            return true
        }
        document.sidecar = sidecar
        dirty = true
        droppedLocalChange = false
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else {
                return
            }
            self?.flush()
        }
        return true
    }

    /// Writes the memo at once (SN-302): it is a file the author also edits
    /// elsewhere, so it is written only if it still holds the bytes this
    /// session last read or wrote, and the written memo becomes the one the
    /// folder watch compares with, so our own write never reloads.
    public func writeMemo(_ memo: Memo) throws(MemoError) {
        guard let url = document.memoURL, let current = document.memo else {
            throw .unreadable("there is no memo")
        }
        guard memo != current else {
            return
        }
        guard (try? Data(contentsOf: url)) == current.bytes else {
            throw .changedOnDisk
        }
        do {
            try memo.bytes.write(to: url, options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        document.memo = memo
    }

    /// Saves a waiting change now; call it before the window closes.
    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard dirty, !isReadOnly else {
            return
        }
        let data = document.sidecar.encoded()
        do {
            try data.write(to: document.sidecarURL, options: .atomic)
            lastSeen = data
            dirty = false
            if saveError != nil {
                saveError = nil
                onMessage?("Saved")
            }
        } catch {
            // A folder on a disk ejected under us is noticed here, since
            // the folder watch may never fire.
            if folderIsThere(), saveError == nil {
                onMessage?("Not saved: \(error.localizedDescription)")
            }
            saveError = error.localizedDescription
        }
    }

    private func diskChanged() {
        // Describes this reload only, so a later one does not report it again.
        droppedLocalChange = false
        if dirty {
            if (try? Data(contentsOf: document.sidecarURL)) == lastSeen {
                flush()
            } else {
                pendingSave?.cancel()
                pendingSave = nil
                dirty = false
                droppedLocalChange = true
            }
        }
        reload()
    }

    /// Reads the folder and sidecar again; a folder that is gone, deleted or
    /// on a disk ejected, keeps the document as it was and says so once.
    public func reload() {
        guard folderIsThere(), !dirty, let fresh = try? CaseDocument.load(folder: document.folder) else {
            return
        }
        lastSeen = fresh.loadedBytes
        let same = fresh.sidecar == document.sidecar
            && fresh.steps == document.steps
            && fresh.memoURL == document.memoURL
            && fresh.memo == document.memo
            && fresh.memoIssue == document.memoIssue
            && fresh.sidecarIssue == document.sidecarIssue
        guard !same else {
            return
        }
        document = fresh
        onReload?()
    }

    /// Whether the case folder exists, saying so when that changes.
    private func folderIsThere() -> Bool {
        let exists = FileManager.default.fileExists(atPath: document.folder.path)
        if exists == folderGone {
            folderGone = !exists
            onMessage?(exists ? "The case folder is back" : "The case folder is gone; changes cannot be saved")
        }
        return exists
    }
}
