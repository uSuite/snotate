import CoreGraphics
import Foundation

/// SN-506: the Settings window's edits to the `styles` file, made on its
/// text so the file stays the truth and a hand-written comment or another
/// preset's block is kept byte for byte. A preset's lines are rewritten in
/// place, missing ones added after its last line, and a preset the file
/// lacks gets a block of its own at the end.
public enum StylesEdit {
    /// One preset's `key value` pairs in the file's order, `name` first and
    /// only when it has one; `counter` is the diameter.
    public static func entries(of style: Style) -> [(key: String, value: String)] {
        var entries: [(key: String, value: String)] = []
        if let name = style.name {
            entries.append(("name", name))
        }
        entries += [
            ("color", hex(style.color)),
            ("stroke", number(style.strokeWidth)),
            ("font", number(style.fontSize)),
            ("counter", number(style.counterRadius * 2)),
            ("blur", number(style.blurRadius)),
        ]
        return entries
    }

    /// `text` with preset `n` set to `style`.
    public static func setting(
        _ n: Int,
        to style: Style,
        in text: String
    ) -> String {
        var lines = split(text)
        let blocks = blockRanges(of: n, in: lines)
        guard let block = blocks.last else {
            if let last = lines.last, last.isEmpty {
                lines.removeLast()
            }
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append("preset \(n)")
            lines += entries(of: style).map { "\($0.key) \($0.value)" }
            return lines.joined(separator: "\n") + "\n"
        }
        if style.name == nil {
            // An earlier block's name would otherwise still apply.
            for range in blocks.reversed() {
                for index in range.reversed() where key(of: lines[index]) == "name" {
                    lines.remove(at: index)
                }
            }
        }
        var range = blockRanges(of: n, in: lines).last ?? block
        for entry in entries(of: style) {
            let matching = range.filter { key(of: lines[$0]) == entry.key }
            if matching.isEmpty {
                let after = range.last { key(of: lines[$0]) != nil } ?? range.lowerBound
                lines.insert("\(entry.key) \(entry.value)", at: after + 1)
                range = range.lowerBound...(range.upperBound + 1)
            } else {
                for index in matching {
                    lines[index] = "\(entry.key) \(entry.value)"
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// `text` without preset `n`'s blocks, and the blank line before each;
    /// for 1 to 3 that brings the built-in preset back.
    public static func removing(
        _ n: Int,
        in text: String
    ) -> String {
        var lines = split(text)
        for range in blockRanges(of: n, in: lines).reversed() {
            let start = range.lowerBound > 0 && lines[range.lowerBound - 1].trimmingCharacters(in: .whitespaces).isEmpty
                ? range.lowerBound - 1
                : range.lowerBound
            lines.removeSubrange(start...range.upperBound)
        }
        return lines.joined(separator: "\n")
    }

    /// The lowest slot no preset fills, `nil` when all nine are taken.
    public static func freeSlot(in styles: Styles) -> Int? {
        (1...9).first { styles.presets[$0] == nil }
    }

    /// Each `preset n` block, from its `preset` line to its last entry, so
    /// comments and blank lines before the next block stay outside it.
    static func blockRanges(
        of n: Int,
        in lines: [String]
    ) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        var start: Int?
        var last = 0
        func close() {
            if let start {
                ranges.append(start...last)
            }
            start = nil
        }
        for (index, line) in lines.enumerated() {
            guard let entry = KeyValueParser.parse(line).first else {
                continue
            }
            if entry.key == "preset" {
                close()
                if Int(entry.value) == n {
                    start = index
                    last = index
                }
            } else if start != nil {
                last = index
            }
        }
        close()
        return ranges
    }

    static func key(of line: String) -> String? {
        KeyValueParser.parse(line).first?.key
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// `#rrggbb`, the only colour form the file takes.
    public static func hex(_ color: RGBA) -> String {
        func byte(_ value: CGFloat) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }

    /// A size with at most two decimals and no trailing zeros, as the
    /// sidecar stores numbers.
    static func number(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}
