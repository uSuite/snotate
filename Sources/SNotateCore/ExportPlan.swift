import Foundation

public enum ExportError: Error, Sendable, Equatable, CustomStringConvertible {
    case readOnly(SidecarError)
    case badFolder(String)
    case unknownStep(String)
    case excluded(String)
    case unreadableImage(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .readOnly(let issue):
            return "the sidecar cannot be read (\(issue)); exporting would replace annotated images with bare ones"
        case .badFolder(let name):
            return "'\(name)' cannot be the export folder: it must be one plain name inside the case folder"
        case .unknownStep(let file):
            return "\(file) is not a step of this case"
        case .excluded(let file):
            return "\(file) is excluded from export"
        case .unreadableImage(let file):
            return "\(file) cannot be decoded"
        case .writeFailed(let reason):
            return "cannot write: \(reason)"
        }
    }
}

/// Which files an export writes and where (SN-401): every step that is not
/// excluded goes to `notated/<same relative path>` with a `.png` extension,
/// so `assets/` is mirrored and a report can point at either folder by one
/// prefix (DECISIONS 2026-10-26). Steps whose image is missing, and steps
/// that would land on the same output, are skipped and reported.
public struct ExportPlan: Sendable {
    public static let defaultFolder = "notated"

    public struct Target: Sendable, Equatable {
        /// The step's sidecar key.
        public let file: String
        /// Relative to the case folder, as the report prints it.
        public let relative: String
        public let output: URL
    }

    public struct Skipped: Sendable, Hashable {
        public let file: String
        public let reason: String
    }

    /// One plain name inside the case folder, never the case folder, a
    /// parent or the assets folder the originals may live in.
    public static func isFolderName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name != CaseDocument.assetsFolder && !name.contains("/")
    }

    public let folder: URL
    public let targets: [Target]
    public let skipped: [Skipped]

    public init(
        document: CaseDocument,
        folderName: String = ExportPlan.defaultFolder,
        format: ExportOptions.Format = .png
    ) throws(ExportError) {
        if let issue = document.sidecarIssue {
            throw .readOnly(issue)
        }
        guard Self.isFolderName(folderName) else {
            throw .badFolder(folderName)
        }
        let folder = document.folder.appendingPathComponent(folderName, isDirectory: true)
        let present = document.steps.filter { !$0.excluded }
        var skipped = document.missing
            .filter { file in !(document.sidecar.steps.first { $0.file == file }?.excluded ?? false) }
            .map { Skipped(file: $0, reason: "image is missing") }
        let outputs = Dictionary(grouping: present, by: { Self.outputPath(for: $0.file, format: format) })
        var targets: [Target] = []
        for step in present {
            let path = Self.outputPath(for: step.file, format: format)
            let sharing = outputs[path, default: []].filter { $0.file != step.file }
            if let other = sharing.first {
                skipped.append(Skipped(file: step.file, reason: "same output as \(other.file)"))
                continue
            }
            targets.append(Target(
                file: step.file,
                relative: folderName + "/" + path,
                output: folder.appendingPathComponent(path)
            ))
        }
        self.folder = folder
        self.targets = targets
        self.skipped = skipped
    }

    /// The output path inside the export folder: the same relative path
    /// with the format's extension.
    public static func outputPath(
        for file: String,
        format: ExportOptions.Format = .png
    ) -> String {
        (file as NSString).deletingPathExtension + "." + format.fileExtension
    }
}
