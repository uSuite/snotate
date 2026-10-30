import Foundation

/// SN-303: the file names `<case-id>-<nn>` that story order asks for, shown
/// to the author and applied only on confirm. It follows the evidence
/// procedure's rename step, so an evidence script finds nothing left to do:
/// captures directly in the case folder, `.png`, `.jpg` or `.jpeg`, two
/// digits widened at 100, never overwriting a file. Before a memo exists
/// every capture is numbered from 00 in story order; once one exists,
/// numbered captures keep their numbers, as the procedure says, others
/// follow the highest number, and a capture the memo references is never
/// renamed (DECISIONS 2026-10-27).
public struct RenamePlan: Sendable, Equatable {
    public struct Rename: Sendable, Equatable {
        public let from: String
        public let to: String
    }

    public struct Kept: Sendable, Equatable {
        public let file: String
        public let reason: String
    }

    public private(set) var renames: [Rename] = []
    public private(set) var kept: [Kept] = []
    /// With a memo: captures whose numbers disagree with story order, which
    /// only moving memo blocks by hand can fix.
    public private(set) var outOfOrder: [String] = []
    /// Why the plan cannot be applied at all.
    public private(set) var blocked: [String] = []

    static let extensions: Set<String> = ["png", "jpg", "jpeg"]

    public init(document: CaseDocument) {
        if let issue = document.sidecarIssue {
            blocked.append("the sidecar cannot be read (\(issue))")
        }
        if document.memoURL != nil, document.memo == nil {
            blocked.append(document.memoIssue.map { "\($0)" } ?? "the memo cannot be read")
        }
        let caseID = document.caseID
        var candidates: [String] = []
        for step in document.steps {
            if step.excluded {
                kept.append(Kept(file: step.file, reason: "excluded: delete it before renaming"))
            } else if step.file.contains("/") {
                kept.append(Kept(file: step.file, reason: "in assets/, which the evidence script leaves alone"))
            } else if !Self.extensions.contains((step.file as NSString).pathExtension.lowercased()) {
                kept.append(Kept(file: step.file, reason: "not a .png or .jpg capture"))
            } else {
                candidates.append(step.file)
            }
        }
        var targets: [String: String] = [:]
        if let memo = document.memo {
            let referenced = Set(memo.entries.map(\.file))
            let rootFiles = document.steps.map(\.file).filter { !$0.contains("/") }
            var next = (rootFiles.compactMap { Self.number(of: $0, caseID: caseID) }.max() ?? -1) + 1
            let pending = candidates.filter { Self.number(of: $0, caseID: caseID) == nil }
            let width = Self.width(next + pending.count)
            var numbers: [(file: String, number: Int)] = []
            for file in candidates {
                if let number = Self.number(of: file, caseID: caseID) {
                    numbers.append((file, number))
                } else if referenced.contains(file) {
                    kept.append(Kept(file: file, reason: "the memo references it"))
                } else {
                    targets[file] = Self.name(caseID, next, width: width, of: file)
                    numbers.append((file, next))
                    next += 1
                }
            }
            var highest = -1
            for entry in numbers {
                if entry.number < highest {
                    outOfOrder.append(targets[entry.file] ?? entry.file)
                }
                highest = max(highest, entry.number)
            }
        } else {
            let width = Self.width(candidates.count)
            for (index, file) in candidates.enumerated() {
                targets[file] = Self.name(caseID, index, width: width, of: file)
            }
        }
        renames = candidates.compactMap { file in
            targets[file].flatMap { $0 == file ? nil : Rename(from: file, to: $0) }
        }
        let sources = Set(renames.map(\.from))
        let present = Set(document.steps.map(\.file))
        for rename in renames where present.contains(rename.to) && !sources.contains(rename.to) {
            blocked.append("\(rename.to) is taken by a capture the plan leaves alone; delete or rename it first")
        }
    }

    public var canApply: Bool {
        blocked.isEmpty && !renames.isEmpty
    }

    /// The number of `<case-id>-<nn>.<ext>`, as the script's pattern reads it.
    static func number(of file: String, caseID: String) -> Int? {
        let ext = (file as NSString).pathExtension.lowercased()
        let stem = (file as NSString).deletingPathExtension
        guard extensions.contains(ext), stem.hasPrefix(caseID + "-") else {
            return nil
        }
        let digits = stem.dropFirst(caseID.count + 1)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        return Int(digits)
    }

    /// The script's `pad_width`: two digits, wider only when needed.
    static func width(_ count: Int) -> Int {
        max(2, String(max(count - 1, 0)).count)
    }

    static func name(_ caseID: String, _ number: Int, width: Int, of file: String) -> String {
        let digits = String(number)
        let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
        return "\(caseID)-\(padded).\((file as NSString).pathExtension.lowercased())"
    }

    public struct Failure: Error, Sendable, Equatable, CustomStringConvertible {
        public let description: String
    }

    /// Renames the captures in `folder` and returns `sidecar` with its keys
    /// following them. Every source is moved to a temporary name first, so
    /// a swap never collides; a file outside the plan is never overwritten,
    /// and a failure puts back what was already moved.
    public func apply(
        in folder: URL,
        sidecar: Sidecar
    ) throws(Failure) -> Sidecar {
        guard blocked.isEmpty else {
            throw Failure(description: blocked.joined(separator: "; "))
        }
        let manager = FileManager.default
        let sources = Set(renames.map(\.from))
        for rename in renames {
            guard manager.fileExists(atPath: folder.appendingPathComponent(rename.from).path) else {
                throw Failure(description: "\(rename.from) is gone")
            }
            if !sources.contains(rename.to), manager.fileExists(atPath: folder.appendingPathComponent(rename.to).path) {
                throw Failure(description: "\(rename.to) already exists")
            }
        }
        let token = UUID().uuidString.prefix(8)
        var done: [(from: URL, to: URL)] = []
        func move(_ from: URL, _ to: URL) throws(Failure) {
            do {
                try manager.moveItem(at: from, to: to)
                done.append((from, to))
            } catch {
                for step in done.reversed() {
                    try? manager.moveItem(at: step.to, to: step.from)
                }
                throw Failure(description: "cannot rename \(from.lastPathComponent): \(error.localizedDescription)")
            }
        }
        let staged = renames.enumerated().map { index, rename in
            (rename, folder.appendingPathComponent(".snotate-rename-\(token)-\(index)"))
        }
        for (rename, temporary) in staged {
            try move(folder.appendingPathComponent(rename.from), temporary)
        }
        for (rename, temporary) in staged {
            try move(temporary, folder.appendingPathComponent(rename.to))
        }
        var renamed = sidecar
        let map = Dictionary(uniqueKeysWithValues: renames.map { ($0.from, $0.to) })
        for index in renamed.steps.indices {
            if let to = map[renamed.steps[index].file] {
                renamed.steps[index].file = to
            }
        }
        return renamed
    }
}
