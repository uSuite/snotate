import CoreGraphics
import Foundation

/// `~/.config/snotate/styles` (SN-210): blocks that start with `preset N`
/// (1 to 9), each line under it one `key value` of the shared grammar:
/// `name` (SN-506), `color #rrggbb`, `stroke`, `font` (size), `counter`
/// (diameter) and `blur`, sizes in image pixels. A block starts from the built-in preset
/// with its number, or built-in preset 1, so it names only what differs;
/// the file adds and overrides presets, never removes them. A bad line is an
/// issue and keeps that value, and a block with a bad `preset` line is
/// skipped (DECISIONS 2026-10-27).
public enum StylesFile {
    public static func parse(_ text: String) -> (styles: Styles, issues: [LineIssue]) {
        var styles = Styles.builtIn
        var issues: [LineIssue] = []
        var current: Int?
        // A bad preset line skips its block without one issue per line.
        var skipping = false
        for entry in KeyValueParser.parse(text) {
            if entry.key == "preset" {
                guard let n = Int(entry.value), (1...9).contains(n) else {
                    issues.append(LineIssue(line: entry.line, message: "preset: '\(entry.value)' is not a number from 1 to 9"))
                    current = nil
                    skipping = true
                    continue
                }
                current = n
                skipping = false
                if styles.presets[n] == nil {
                    // Preset 1's values, but not its name.
                    var style = Styles.builtIn.style(for: n)
                    if Styles.builtIn.presets[n] == nil {
                        style.name = nil
                    }
                    styles.presets[n] = style
                }
                continue
            }
            guard let n = current else {
                if !skipping {
                    issues.append(LineIssue(line: entry.line, message: "\(entry.key) comes before any preset line"))
                }
                continue
            }
            do {
                try set(entry.key, entry.value, on: &styles.presets[n]!)
            } catch {
                issues.append(LineIssue(line: entry.line, message: error.description))
            }
        }
        return (styles, issues)
    }

    struct BadLine: Error, CustomStringConvertible {
        let description: String
    }

    static func set(_ key: String, _ value: String, on style: inout Style) throws(BadLine) {
        switch key {
        case "name":
            guard (1...nameLimit).contains(value.count) else {
                throw BadLine(description: "name: '\(value)' is not 1 to \(nameLimit) characters")
            }
            style.name = value
        case "color":
            guard value.count == 7, value.hasPrefix("#"), let hex = UInt32(value.dropFirst(), radix: 16) else {
                throw BadLine(description: "color: '\(value)' is not #rrggbb")
            }
            style.color = RGBA(hex: hex)
        case "stroke":
            style.strokeWidth = try size(key, value, ranges[key]!)
        case "font":
            style.fontSize = try size(key, value, ranges[key]!)
        case "counter":
            style.counterRadius = try size(key, value, ranges[key]!) / 2
        case "blur":
            style.blurRadius = try size(key, value, ranges[key]!)
        default:
            throw BadLine(description: "unknown style '\(key)'")
        }
    }

    private static func size(
        _ key: String,
        _ value: String,
        _ range: ClosedRange<CGFloat>
    ) throws(BadLine) -> CGFloat {
        guard let number = Double(value), range.contains(CGFloat(number)) else {
            throw BadLine(description: "\(key): '\(value)' is not a size from \(format(range.lowerBound)) to \(format(range.upperBound)) pixels")
        }
        return CGFloat(number)
    }

    /// The longest name, so it fits the Preset menu and the Settings list.
    public static let nameLimit = 40

    /// The range each size key accepts, for the Settings window's fields;
    /// `counter` is the diameter, as the file writes it.
    public static let ranges: [String: ClosedRange<CGFloat>] = [
        "stroke": 0.5...64,
        "font": 6...400,
        "counter": 8...400,
        "blur": 1...200,
    ]

    static func format(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(Double(value))
    }

    /// Written on first run: the built-in presets, so the file documents
    /// itself and an untouched one changes nothing.
    public static let defaultText = """
        # sNotate styles. A block per preset: `preset N` (1 to 9, the keys
        # that pick it), then any of these, sizes in image pixels:
        #   name text   color #rrggbb   stroke width   font size
        #   counter diameter   blur radius
        # A block starts from built-in preset N (or 1), so name only what
        # differs. Edits apply at once, as do changes from sNotate > Settings.
        # The report palette: primary blue, danger red, growth green.

        preset 1
        name Primary
        color #00579C
        stroke 4
        font 28
        counter 36
        blur 12

        preset 2
        name Danger
        color #C62828
        stroke 6
        font 36
        counter 48
        blur 16

        preset 3
        name Growth
        color #00897B
        stroke 2
        font 20
        counter 28
        blur 8

        """
}
