import Foundation
import SCommon

/// The keymap in sections, for the `?` overlay (SN-503) and docs/keys.md,
/// so the two cannot disagree. Sections come from the built-in keymap's
/// comments: one after a blank line starts a section, one after a binding a
/// subsection. Against a live keymap, a built-in line is kept only while
/// its keys still do the same thing, and the user's own bindings follow
/// under "Your keymap".
public enum KeyHelp {
    public struct Row: Sendable, Equatable {
        /// As `Key.description` writes them: `j`, `gg`, `<cmd-z>`.
        public let keys: String
        /// As the keymap writes it: `tool arrow`.
        public let command: String
    }

    public struct Section: Sendable, Equatable {
        public let title: String
        /// False for a subsection, which continues the section before it.
        public let isMain: Bool
        public var rows: [Row]
    }

    public static let yourKeymap = "Your keymap"

    public static func sections(
        defaultText: String = DefaultKeymap.text,
        keymap live: Keymap<Command>? = nil
    ) -> [Section] {
        let builtIn = Keymap<Command>.parse(defaultText).keymap
        var sections: [Section] = []
        var previousBlank = false
        var seenBinding = false
        for raw in defaultText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                previousBlank = true
                continue
            }
            defer {
                previousBlank = false
            }
            if line.hasPrefix("#") {
                let text = line.drop { $0 == "#" || $0 == " " }
                guard seenBinding || previousBlank, !text.isEmpty else {
                    continue
                }
                sections.append(Section(title: text.prefix(1).uppercased() + text.dropFirst(), isMain: previousBlank, rows: []))
                continue
            }
            guard let entry = KeyValueParser.parse(line).first,
                let keys = try? Key.parseSequence(entry.key)
            else {
                continue
            }
            seenBinding = true
            if let live, live.command(for: keys) != builtIn.command(for: keys) {
                continue
            }
            guard !sections.isEmpty else {
                continue
            }
            sections[sections.count - 1].rows.append(Row(keys: shown(keys), command: entry.value))
        }
        if let live {
            let own = live.bindings.filter { builtIn.command(for: $0.keys) != $0.command }
            if !own.isEmpty {
                sections.append(Section(title: yourKeymap, isMain: true, rows: own.map { Row(keys: shown($0.keys), command: $0.text) }))
            }
        }
        return sections.filter { !$0.rows.isEmpty }
    }

    static func shown(_ keys: [Key]) -> String {
        keys.map(\.description).joined()
    }
}
