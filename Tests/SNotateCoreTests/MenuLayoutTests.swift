import CoreGraphics
import Foundation
import Testing
@testable import SCommon
@testable import SNotateCore

/// SN-505: the menu bar against the keymap.
struct MenuLayoutTests {
    private func overlaid(_ text: String) -> Keymap<Command> {
        Keymap<Command>.overlaid(text, over: DefaultKeymap.keymap).keymap
    }

    @Test func settingsComeFirstInTheAppMenu() {
        let app = MenuLayout.menus[0].entries
        #expect(app.contains(.app("Settings…", .settings)))
        #expect(app.firstIndex(of: .app("Settings…", .settings))! < app.firstIndex(of: .app("Open Config Folder", .openConfigFolder))!)
        // cmd-, belongs to the Settings item, so no binding may take it.
        #expect(!DefaultKeymap.text.contains("cmd-,"))
    }

    @Test func everyBoundCommandIsInAMenuButTheNudges() {
        let inMenus = MenuLayout.commands
        for binding in DefaultKeymap.keymap.bindings {
            if case .nudge = binding.command {
                continue
            }
            #expect(inMenus.contains(binding.command), "\(binding.text) is in no menu")
        }
    }

    @Test func eachCommandIsInTheMenusOnceAndReadsBackFromItsName() throws {
        let commands = MenuLayout.commands
        #expect(Set(commands.map { $0.name ?? "" }).count == commands.count)
        for command in commands {
            let name = try #require(command.name)
            #expect(try Command.parse(name) == command)
        }
    }

    @Test func chordsAreShortcutsAndOtherKeysAreText() {
        let keymap = DefaultKeymap.keymap
        #expect(MenuLayout.keys(for: .undo, macKey: nil, in: keymap) == .init(shortcut: Key("z", modifiers: .command), text: nil))
        #expect(MenuLayout.keys(for: .next, macKey: nil, in: keymap) == .init(shortcut: nil, text: "j"))
        #expect(MenuLayout.keys(for: .first, macKey: nil, in: keymap) == .init(shortcut: nil, text: "gg"))
        #expect(MenuLayout.keys(for: .zoomIn, macKey: "cmd-=", in: keymap) == .init(shortcut: Key("=", modifiers: .command), text: "+"))
    }

    @Test func aRebindingMovesTheShortcut() {
        let keymap = overlaid("cmd-j next\ncmd-e nop\ncmd-x export\n")
        #expect(MenuLayout.keys(for: .next, macKey: nil, in: keymap).shortcut == Key("j", modifiers: .command))
        #expect(MenuLayout.keys(for: .exportCase, macKey: nil, in: keymap).shortcut == Key("x", modifiers: .command))
    }

    @Test func withoutACaseOnlyHelpAndTheConfigAreAvailable() {
        for command in MenuLayout.commands {
            #expect(Dispatcher.isAvailable(command, in: nil) == [.help, .exportConfig("")].contains(command), "\(command)")
        }
    }

    @Test func availabilityFollowsSelectionHistoryAndReadOnly() throws {
        let counter = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))
        var fixture = try EditorFixture(items: [counter])
        #expect(!Dispatcher.isAvailable(.delete, in: fixture.state))
        #expect(!Dispatcher.isAvailable(.undo, in: fixture.state))
        #expect(Dispatcher.isAvailable(.selectAll, in: fixture.state))
        #expect(Dispatcher.isAvailable(.next, in: fixture.state))
        fixture.run(.select([counter.id]))
        fixture.run(.duplicate)
        #expect(Dispatcher.isAvailable(.delete, in: fixture.state))
        #expect(Dispatcher.isAvailable(.undo, in: fixture.state))
        #expect(!Dispatcher.isAvailable(.redo, in: fixture.state))
        let readOnly = try EditorFixture(items: [counter], sidecar: Data("<<<<<<< HEAD\n".utf8))
        #expect(!Dispatcher.isAvailable(.exclude, in: readOnly.state))
        #expect(Dispatcher.isAvailable(.next, in: readOnly.state))
        #expect(Dispatcher.isAvailable(.viewStoryboard, in: readOnly.state))
    }
}
