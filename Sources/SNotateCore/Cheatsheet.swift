import Foundation
import SCommon

/// The key cheat sheet, docs/keys.md (SN-604), generated from the built-in
/// keymap so the documentation never drifts from the bindings, after
/// sView's, in the sections the `?` overlay shows (`KeyHelp`). Commands
/// with no key, reached through the `:` line, follow.
public enum Cheatsheet {
    /// The `:` line forms that no default key reaches, with what they do.
    static let commandLineOnly: [(form: String, text: String)] = [
        ("<n>", "go to step n; `go-to <n>` is the same"),
        ("excluded", "list the excluded steps"),
        ("deselect", "clear the selection"),
        ("end-text-edit", "finish typing into a text annotation"),
        ("stamp-next", "stamp the selected blur and highlight regions, or the crop while cropping, onto the next step"),
        ("stamp-all", "the same onto every other step"),
        ("rename-plan", "show the renames story order asks for, applied only on confirm"),
        ("set <key> <value>", "change one line of ~/.config/snotate/config"),
        ("export-config [path]", "zip config, keymap and styles, to the Desktop by default"),
    ]

    public static func markdown(keymapText: String = DefaultKeymap.text) -> String {
        var out = [
            "# sNotate keys",
            "",
            "Generated from the built-in keymap by `make cheatsheet`; do not edit by hand. Lines in `~/.config/snotate/keymap` apply on top of these, and `<keys> nop` removes one. Digits choose a style preset, so there are no count prefixes. Hold `space` and drag to pan.",
        ]
        for section in KeyHelp.sections(defaultText: keymapText) {
            out += ["", (section.isMain ? "## " : "### ") + section.title, "", "| Keys | Command |", "| --- | --- |"]
            out += section.rows.map { "| `\($0.keys.replacingOccurrences(of: "|", with: "\\|"))` | \($0.command) |" }
        }
        out += [
            "",
            "## Command line only",
            "",
            "Typed after `:`; any command above works there too, as the keymap writes it.",
            "",
            "| Command | Does |",
            "| --- | --- |",
        ]
        out += commandLineOnly.map { "| `:\($0.form)` | \($0.text) |" }
        return out.joined(separator: "\n") + "\n"
    }
}
