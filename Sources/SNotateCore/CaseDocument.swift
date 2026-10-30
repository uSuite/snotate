import Foundation

/// One image of the case, in story order, with what the sidecar says about it.
public struct CaseStep: Sendable, Equatable {
    /// Path relative to the case folder, the sidecar key.
    public let file: String
    public let url: URL
    /// Pixel size on disk, `nil` when the header cannot be read.
    public let size: PixelSize?
    /// How recorded annotations map onto the image, `nil` when either size
    /// is unknown.
    public let scale: StepScale?
    public let excluded: Bool
}

/// A case folder opened for notation (SN-101 to SN-104): its images in story
/// order, the memo beside them and the sidecar, merged so that the sidecar's
/// order wins, new images take their place after the step they follow by name,
/// and entries whose image is gone are kept and listed. Loading never writes;
/// what loading added (new images, missing sizes) reaches the disk with the
/// first real change.
public struct CaseDocument: Sendable, Equatable {
    /// Captures may sit in this sub-folder, as in some real cases.
    public static let assetsFolder = "assets"

    public let folder: URL
    public let caseID: String
    public let pocCase: PocCase?
    public let memoURL: URL?
    /// The memo as read, `nil` when there is none or it cannot be read.
    public var memo: Memo?
    /// Why an existing memo could not be read; the case still opens.
    public let memoIssue: MemoError?
    public let sidecarURL: URL
    /// Every entry in order, those whose image is missing included.
    public var sidecar: Sidecar
    /// Why the sidecar on disk could not be read; the document is then built
    /// from the folder alone and must not be saved over it.
    public let sidecarIssue: SidecarError?
    /// Images found that the sidecar on disk did not list, in story order.
    public let added: [String]
    /// The sidecar bytes as loaded, `nil` when there was no file.
    let loadedBytes: Data?
    private let images: [String: ImageFile]

    struct ImageFile: Sendable, Equatable {
        let url: URL
        let size: PixelSize?
    }

    public var steps: [CaseStep] {
        sidecar.steps.compactMap { entry in
            guard let image = images[entry.file] else {
                return nil
            }
            let scale = entry.size.flatMap { recorded in
                image.size.map { StepScale(recorded: recorded, actual: $0) }
            }
            return CaseStep(
                file: entry.file,
                url: image.url,
                size: image.size,
                scale: scale,
                excluded: entry.excluded
            )
        }
    }

    /// Sidecar entries whose image is not in the folder (SN-104).
    public var missing: [String] {
        sidecar.steps.map(\.file).filter { images[$0] == nil }
    }

    /// A case folder, or an image inside it (or inside its `assets/`), with
    /// the index of that image's step.
    public static func open(_ url: URL) throws -> (document: CaseDocument, selected: Int?) {
        var isDirectory: ObjCBool = false
        // A typo in a case name must not open the folder around it.
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NoSuchPath()
        }
        if isDirectory.boolValue {
            return (try load(folder: url), nil)
        }
        var folder = url.deletingLastPathComponent()
        var file = url.lastPathComponent
        if folder.lastPathComponent == assetsFolder {
            folder = folder.deletingLastPathComponent()
            file = assetsFolder + "/" + file
        }
        let document = try load(folder: folder)
        return (document, document.steps.firstIndex { $0.file == file })
    }

    public struct NoSuchPath: LocalizedError, Equatable, CustomStringConvertible {
        public var description: String { "no such file or folder" }
        /// The open alert's text.
        public var errorDescription: String? { description }
    }

    public static func load(folder: URL) throws -> CaseDocument {
        let caseID = folder.lastPathComponent
        var images: [String: ImageFile] = [:]
        for item in try FolderScanner.images(in: folder) {
            images[item.name] = ImageFile(url: item.url, size: PixelSize(imageAt: item.url))
        }
        let assets = folder.appendingPathComponent(assetsFolder, isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: assets.path, isDirectory: &isDirectory), isDirectory.boolValue {
            for item in try FolderScanner.images(in: assets) {
                images[assetsFolder + "/" + item.name] = ImageFile(url: item.url, size: PixelSize(imageAt: item.url))
            }
        }

        let sidecarURL = folder.appendingPathComponent(caseID + ".snotate.json")
        let loadedBytes = try? Data(contentsOf: sidecarURL)
        var sidecar = Sidecar()
        var issue: SidecarError?
        if let loadedBytes {
            do {
                sidecar = try Sidecar.decode(loadedBytes)
            } catch {
                issue = error
            }
        }

        let order = evidenceOrder(Array(images.keys), caseID: caseID)
        var known = Set(sidecar.steps.map(\.file))
        var new: Set<String> = []
        for (index, file) in order.enumerated() where !known.contains(file) {
            let previous = order[..<index].last { known.contains($0) }
            let position = previous.flatMap { previous in
                sidecar.steps.firstIndex { $0.file == previous }
            }
            sidecar.steps.insert(
                SidecarStep(file: file, size: images[file]?.size),
                at: position.map { $0 + 1 } ?? 0
            )
            known.insert(file)
            new.insert(file)
        }
        for index in sidecar.steps.indices where sidecar.steps[index].size == nil {
            sidecar.steps[index].size = images[sidecar.steps[index].file]?.size
        }

        let memoURL = folder.appendingPathComponent(caseID + ".md")
        let hasMemo = FileManager.default.fileExists(atPath: memoURL.path)
        var memo: Memo?
        var memoIssue: MemoError?
        if hasMemo {
            do {
                memo = try Memo.read(memoURL)
            } catch {
                memoIssue = error
            }
        }
        return CaseDocument(
            folder: folder,
            caseID: caseID,
            pocCase: PocCase(folderName: caseID),
            memoURL: hasMemo ? memoURL : nil,
            memo: memo,
            memoIssue: memoIssue,
            sidecarURL: sidecarURL,
            sidecar: sidecar,
            sidecarIssue: issue,
            added: sidecar.steps.map(\.file).filter(new.contains),
            loadedBytes: loadedBytes,
            images: images
        )
    }

    /// The order the evidence procedure gives: renamed `<case-id>-<nn>`
    /// captures by number, then the rest by natural name, which for
    /// `<tool>-YYYY-MM-DD-HHMMSS` is capture time.
    static func evidenceOrder(_ files: [String], caseID: String) -> [String] {
        func number(_ file: String) -> Int? {
            let stem = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            let prefix = caseID + "-"
            guard stem.hasPrefix(prefix) else {
                return nil
            }
            let digits = stem.dropFirst(prefix.count)
            return digits.allSatisfy(\.isASCII) ? Int(digits) : nil
        }
        return files.sorted { lhs, rhs in
            switch (number(lhs), number(rhs)) {
            case (let l?, let r?) where l != r:
                return l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                let lname = (lhs as NSString).lastPathComponent
                let rname = (rhs as NSString).lastPathComponent
                if lname != rname {
                    return Sorter.naturalLess(lname, rname)
                }
                return Sorter.naturalLess(lhs, rhs)
            }
        }
    }
}
