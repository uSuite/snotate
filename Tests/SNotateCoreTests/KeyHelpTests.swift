import Foundation
import Testing
@testable import SCommon
@testable import SNotateCore

/// SN-503: the sections the `?` overlay and docs/keys.md share.
struct KeyHelpTests {
    private func overlaid(_ text: String) -> Keymap<Command> {
        Keymap<Command>.overlaid(text, over: DefaultKeymap.keymap).keymap
    }

    @Test func helpIsTheBuiltInKeymapWhenNothingIsRebound() {
        let builtIn = KeyHelp.sections()
        #expect(KeyHelp.sections(keymap: DefaultKeymap.keymap) == builtIn)
        #expect(builtIn.first?.title == "Steps")
        #expect(builtIn.first?.rows.first == KeyHelp.Row(keys: "j", command: "next"))
        #expect(builtIn.last?.rows == [KeyHelp.Row(keys: "?", command: "help")])
        #expect(!builtIn.contains { $0.title == KeyHelp.yourKeymap })
    }

    @Test func helpDropsWhatTheUserReboundAndListsTheirOwn() throws {
        let sections = KeyHelp.sections(keymap: overlaid("a nop\nx tool arrow\nQ zoom-fit\n"))
        let rows = sections.flatMap(\.rows)
        #expect(!rows.contains(KeyHelp.Row(keys: "a", command: "tool arrow")))
        #expect(!rows.contains(KeyHelp.Row(keys: "x", command: "exclude")))
        let own = try #require(sections.last)
        #expect(own.title == KeyHelp.yourKeymap)
        #expect(own.rows == [KeyHelp.Row(keys: "x", command: "tool arrow"), KeyHelp.Row(keys: "Q", command: "zoom-fit")])
    }
}
