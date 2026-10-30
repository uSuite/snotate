import Foundation

/// SN-506: one preset as a `.snotatepreset` file, the way Terminal exports a
/// profile: a header comment and the `key value` lines of one `styles` block
/// without its `preset` line, so it is plain text, diffs well and can be
/// pasted under a `preset N` line by hand. The slot is chosen on import.
public enum PresetFile {
    public static let fileExtension = "snotatepreset"

    static let header = "# sNotate preset: import it in sNotate > Settings > Presets, or paste it under a `preset N` line in styles."

    public static func text(of style: Style) -> String {
        ([header] + StylesEdit.entries(of: style).map { "\($0.key) \($0.value)" }).joined(separator: "\n") + "\n"
    }

    /// The preset in `text`, starting from built-in preset 1 without its
    /// name, so a file naming only `color` still gives a whole preset; a bad
    /// line is an issue and keeps that value, as in the styles file.
    public static func parse(_ text: String) -> (style: Style, issues: [LineIssue]) {
        var style = Styles.builtIn.style(for: 1)
        style.name = nil
        var issues: [LineIssue] = []
        for entry in KeyValueParser.parse(text) {
            if entry.key == "preset" {
                issues.append(LineIssue(line: entry.line, message: "a preset file holds one preset and no preset line"))
                continue
            }
            do {
                try StylesFile.set(entry.key, entry.value, on: &style)
            } catch {
                issues.append(LineIssue(line: entry.line, message: error.description))
            }
        }
        return (style, issues)
    }

    /// The file name an export suggests: the name, made safe for a file,
    /// or `preset-N`.
    public static func suggestedName(
        for style: Style,
        slot: Int
    ) -> String {
        let safe = (style.name ?? "")
            .map { "/:\\".contains($0) ? "-" : $0 }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespaces)
        return (safe.isEmpty ? "preset-\(slot)" : safe) + "." + fileExtension
    }
}
