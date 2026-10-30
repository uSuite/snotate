import Foundation

/// SN-405: the case folders under a PoC root, for exporting a whole tree.
/// A folder with its own sidecar or captures is a case and is not looked
/// into further; any other folder is walked, skipping hidden folders and
/// those named like the export folder or `assets`. Cases without a sidecar
/// are found but not exported: bare copies of every capture would only be
/// noise (DECISIONS 2026-10-27).
public enum CaseWalker {
    public struct Found: Sendable, Equatable {
        public var withSidecar: [URL] = []
        public var withoutSidecar: [URL] = []
    }

    /// Whether `folder` is itself a case rather than a root to walk.
    public static func isCase(_ folder: URL) -> Bool {
        hasSidecar(folder) || CaseSiblings.hasCaptures(folder)
    }

    public static func cases(
        under root: URL,
        notatedDir: String = ExportPlan.defaultFolder
    ) -> Found {
        var found = Found()
        walk(root, notatedDir: notatedDir, into: &found)
        return found
    }

    private static func walk(
        _ folder: URL,
        notatedDir: String,
        into found: inout Found
    ) {
        guard let children = try? FolderScanner.subfolders(of: folder) else {
            return
        }
        for child in children where ![notatedDir, CaseDocument.assetsFolder].contains(child.lastPathComponent) {
            if hasSidecar(child) {
                found.withSidecar.append(child)
            } else if CaseSiblings.hasCaptures(child) {
                found.withoutSidecar.append(child)
            } else {
                walk(child, notatedDir: notatedDir, into: &found)
            }
        }
    }

    static func hasSidecar(_ folder: URL) -> Bool {
        let name = folder.standardizedFileURL.lastPathComponent
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".snotate.json").path)
    }
}
