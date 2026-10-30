import Foundation

public enum MemoError: Error, Sendable, Equatable, CustomStringConvertible {
    case notUTF8
    case unreadable(String)
    case noReference(String)
    case multiline
    case changedOnDisk
    case writeFailed(String)

    public var description: String {
        switch self {
        case .notUTF8:
            return "the memo is not UTF-8 text"
        case .unreadable(let reason):
            return "the memo cannot be read: \(reason)"
        case .noReference(let file):
            return "the memo does not reference \(file)"
        case .multiline:
            return "a caption is one line"
        case .changedOnDisk:
            return "the memo changed on disk since it was read"
        case .writeFailed(let reason):
            return "the memo cannot be written: \(reason)"
        }
    }
}

/// The case memo `<case-id>.md` (SN-302): for each capture a `- caption`
/// bullet above its `![...](<file>)` line, as the evidence procedure writes
/// it. The memo is kept as lines with their own endings so that a caption
/// edit changes one line and leaves every other byte as it was. No Markdown
/// parser: a bullet is an unindented `- `, `* ` or `+ ` line, and the one for
/// an image is the first unindented line above it, past blank lines and
/// indented sub-bullets.
public struct Memo: Sendable, Equatable {
    /// The text the evidence script writes before an author fills it in.
    public static let placeholder = "description"

    public struct Line: Sendable, Equatable {
        public var text: String
        /// `"\n"`, `"\r\n"`, or `""` for a last line without one.
        public var ending: String
    }

    public struct Entry: Sendable, Equatable {
        /// The referenced path as a step key: relative, `./` dropped, decoded.
        public let file: String
        public let imageLine: Int
        public let bulletLine: Int?
        /// The bullet's text without marker and trailing whitespace.
        public let caption: String?
        /// Indented lines between the bullet and the image, as written.
        public let details: [String]

        public var isPlaceholder: Bool { caption == Memo.placeholder }
    }

    public private(set) var lines: [Line]
    private var byteOrderMark: Bool

    public init(data: Data) throws(MemoError) {
        // Foundation drops a leading byte-order mark when decoding, so it is
        // detected on the bytes and written back from the flag.
        byteOrderMark = data.starts(with: [0xEF, 0xBB, 0xBF])
        guard let text = String(data: byteOrderMark ? data.dropFirst(3) : data, encoding: .utf8) else {
            throw .notUTF8
        }
        lines = Self.split(text)
    }

    public var bytes: Data {
        var text = byteOrderMark ? "\u{FEFF}" : ""
        for line in lines {
            text += line.text + line.ending
        }
        return Data(text.utf8)
    }

    /// Every image reference outside code fences, in memo order.
    public var entries: [Entry] {
        var result: [Entry] = []
        var fenced = false
        for (index, line) in lines.enumerated() {
            let trimmed = line.text.drop { $0 == " " || $0 == "\t" }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fenced.toggle()
                continue
            }
            guard !fenced else {
                continue
            }
            for file in Self.imagePaths(in: line.text) {
                result.append(entry(file: file, imageLine: index))
            }
        }
        return result
    }

    /// The caption entry for a step: the first reference to `file`.
    public func entry(for file: String) -> Entry? {
        entries.first { $0.file == file }
    }

    public func references(to file: String) -> [Entry] {
        entries.filter { $0.file == file }
    }

    /// The memo's bytes with `caption` as the caption of `file`'s first
    /// reference: that bullet line rewritten, keeping its marker, trailing
    /// whitespace and ending, or, when the image has no bullet, `- caption`
    /// and a blank line inserted above the image (with a blank line before it
    /// when the line above is text). Nothing else changes.
    public func settingCaption(
        _ caption: String,
        for file: String
    ) throws(MemoError) -> Data {
        guard !caption.contains(where: \.isNewline) else {
            throw .multiline
        }
        guard let entry = entry(for: file) else {
            throw .noReference(file)
        }
        var memo = self
        if let index = entry.bulletLine, let bullet = Self.bullet(lines[index].text) {
            memo.lines[index].text = bullet.marker + caption + bullet.trailing
        } else {
            let ending = lines[entry.imageLine].ending.isEmpty ? defaultEnding : lines[entry.imageLine].ending
            var inserted = [
                Line(text: "- " + caption, ending: ending),
                Line(text: "", ending: ending),
            ]
            let above = entry.imageLine - 1
            if above >= 0, !lines[above].text.allSatisfy({ $0 == " " || $0 == "\t" }) {
                inserted.insert(Line(text: "", ending: ending), at: 0)
            }
            memo.lines.insert(contentsOf: inserted, at: entry.imageLine)
        }
        return memo.bytes
    }

    /// The memo without `file`'s blocks (SN-309): for each reference on a
    /// line of its own, the bullet, its indented details, the image line and
    /// one blank line next to them, after the block when there is one, so
    /// the evidence script's spacing stays even. A reference sharing its line
    /// with other text is left and counted in `kept`. Nothing else changes.
    public func removingReferences(to file: String) -> (memo: Memo, kept: Int) {
        var memo = self
        var kept = 0
        for entry in references(to: file).reversed() {
            let line = lines[entry.imageLine].text
            let rest = line.replacing(/!\[[^\]]*\]\([^)]*\)/, with: "")
            guard Self.imagePaths(in: line) == [file], rest.allSatisfy({ $0 == " " || $0 == "\t" }) else {
                kept += 1
                continue
            }
            var start = entry.bulletLine ?? entry.imageLine
            var end = entry.imageLine
            func blank(_ index: Int) -> Bool {
                memo.lines.indices.contains(index) && memo.lines[index].text.allSatisfy { $0 == " " || $0 == "\t" }
            }
            if blank(end + 1) {
                end += 1
            } else if blank(start - 1) {
                start -= 1
            }
            memo.lines.removeSubrange(start...end)
        }
        return (memo, kept)
    }

    /// The ending the file already uses, LF for a one-line file.
    private var defaultEnding: String {
        lines.first { !$0.ending.isEmpty }?.ending ?? "\n"
    }

    private func entry(file: String, imageLine: Int) -> Entry {
        var index = imageLine - 1
        var details: [String] = []
        while index >= 0 {
            let text = lines[index].text
            if text.allSatisfy({ $0 == " " || $0 == "\t" }) {
                index -= 1
            } else if text.first == " " || text.first == "\t" {
                details.insert(text, at: 0)
                index -= 1
            } else {
                break
            }
        }
        guard index >= 0, let bullet = Self.bullet(lines[index].text) else {
            return Entry(
                file: file,
                imageLine: imageLine,
                bulletLine: nil,
                caption: nil,
                details: []
            )
        }
        return Entry(
            file: file,
            imageLine: imageLine,
            bulletLine: index,
            caption: bullet.caption,
            details: details
        )
    }

    /// A bullet line's parts: marker with its spaces, caption, and the
    /// trailing whitespace after the caption.
    static func bullet(_ text: String) -> (marker: String, caption: String, trailing: String)? {
        guard let match = text.wholeMatch(of: /([-*+] +)(.*?)([ \t]*)/) else {
            return nil
        }
        return (String(match.1), String(match.2), String(match.3))
    }

    /// Paths of the `![alt](path)` and `![alt](<path> "title")` references on
    /// one line, normalised to step keys.
    static func imagePaths(in text: String) -> [String] {
        text.matches(of: /!\[[^\]]*\]\(\s*(<[^>]*>|[^)\s]+)(?:\s+"[^"]*")?\s*\)/).map { match in
            var path = String(match.1)
            if path.hasPrefix("<"), path.hasSuffix(">") {
                path = String(path.dropFirst().dropLast())
            }
            path = path.removingPercentEncoding ?? path
            while path.hasPrefix("./") {
                path.removeFirst(2)
            }
            return path
        }
    }

    /// Lines with their endings; `"\r\n"` is one Character in Swift, so a
    /// CRLF never splits.
    private static func split(_ text: String) -> [Line] {
        var lines: [Line] = []
        var current = ""
        for character in text {
            if character == "\n" || character == "\r\n" {
                lines.append(Line(text: current, ending: String(character)))
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            lines.append(Line(text: current, ending: ""))
        }
        return lines
    }
}

extension Memo {
    public static func read(_ url: URL) throws(MemoError) -> Memo {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        return try Memo(data: data)
    }

    /// Writes `caption` for `file` into the memo at `url` and returns the
    /// memo as written. The file must still hold this memo's bytes: an edit
    /// made elsewhere since it was read is never overwritten.
    public func writeCaption(
        _ caption: String,
        for file: String,
        to url: URL
    ) throws(MemoError) -> Memo {
        let updated = try settingCaption(caption, for: file)
        guard (try? Data(contentsOf: url)) == bytes else {
            throw .changedOnDisk
        }
        do {
            try updated.write(to: url, options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        return try Memo(data: updated)
    }
}
