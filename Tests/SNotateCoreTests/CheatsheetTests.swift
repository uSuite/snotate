import Foundation
import Testing
@testable import SCommon
@testable import SNotateCore

struct CheatsheetTests {
    @Test func sectionsSubheadingsAndEscapedKeys() {
        let text = """
            # header comment, skipped
            # also skipped

            # steps
            j next
            # views
            | flip

            # tools
            gg first
            """
        #expect(
            Cheatsheet.markdown(keymapText: text).contains(
                """
                ## Steps

                | Keys | Command |
                | --- | --- |
                | `j` | next |

                ### Views

                | Keys | Command |
                | --- | --- |
                | `\\|` | flip |

                ## Tools

                | Keys | Command |
                | --- | --- |
                | `gg` | first |

                ## Command line only
                """
            )
        )
    }

    @Test func everyDefaultBindingIsListed() {
        let sheet = Cheatsheet.markdown()
        for binding in DefaultKeymap.keymap.bindings {
            #expect(sheet.contains("| \(binding.text) |"), "\(binding.text)")
        }
        #expect(!sheet.contains("\u{2014}"))
    }

    /// A command with a name but no default key must be on the sheet's
    /// command-line list, and everything listed must parse.
    @Test func everyCommandIsReachableFromTheSheet() throws {
        let bound = Set(DefaultKeymap.text.split(separator: "\n").compactMap { line -> String? in
            let words = line.split(separator: " ")
            return words.count >= 2 && !line.hasPrefix("#") ? String(words[1]) : nil
        })
        let listed = Set(Cheatsheet.commandLineOnly.map { String($0.form.split(separator: " ")[0]) })
        for name in Command.simple.keys where !bound.contains(name) {
            #expect(listed.contains(name), "\(name) has no key and is not on the sheet")
        }
        for (form, _) in Cheatsheet.commandLineOnly {
            let example = form
                .replacingOccurrences(of: "<n>", with: "3")
                .replacingOccurrences(of: "<key> <value>", with: "snap true")
                .replacingOccurrences(of: " [path]", with: "")
            _ = try Command.parseCommandLine(example)
        }
    }

    /// docs/keys.md must be what `make cheatsheet` writes now.
    @Test func committedCheatsheetIsCurrent() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let committed = try String(contentsOf: repo.appendingPathComponent("docs/keys.md"), encoding: .utf8)
        #expect(committed == Cheatsheet.markdown(), "run make cheatsheet")
    }
}
