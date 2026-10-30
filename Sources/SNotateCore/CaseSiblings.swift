import Foundation
import SCommon

/// The case folders beside an open one, for `case-next` and
/// `case-previous` (SN-501). Inside a PoC tree only folders named like a
/// case count, so product folders, `golden/` or a stray folder of PNGs are
/// skipped; elsewhere any folder with images counts, as in sView. Folders
/// without captures (directly or in `assets/`) are skipped either way, in
/// natural order (DECISIONS 2026-10-27).
public enum CaseSiblings {
    /// The sibling `offset` cases away, `nil` past the first or last.
    public static func sibling(
        of folder: URL,
        offset: Int
    ) -> URL? {
        guard offset != 0, let parent = FolderTree.parent(of: folder),
            let siblings = try? FolderScanner.subfolders(of: parent)
        else {
            return nil
        }
        let name = folder.standardizedFileURL.lastPathComponent
        let named = PocCase(folderName: name) != nil
        let cases = siblings.filter { candidate in
            candidate.lastPathComponent == name
                || ((!named || PocCase(folderName: candidate.lastPathComponent) != nil) && hasCaptures(candidate))
        }
        guard let index = cases.firstIndex(where: { $0.lastPathComponent == name }) else {
            return nil
        }
        let target = index + offset
        guard cases.indices.contains(target) else {
            return nil
        }
        return cases[target]
    }

    static func hasCaptures(_ folder: URL) -> Bool {
        FolderTree.hasImages(folder) || FolderTree.hasImages(folder.appendingPathComponent(CaseDocument.assetsFolder))
    }
}
