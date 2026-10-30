import Foundation
import Testing
@testable import SNotateCore

struct DefaultKeymapTests {
    private func command(_ keys: String) throws -> Command? {
        DefaultKeymap.keymap.command(for: try Key.parseSequence(keys))
    }

    @Test func everyLineParses() {
        #expect(Keymap<Command>.parse(DefaultKeymap.text).issues.isEmpty)
    }

    @Test func theCoreBindingsAreThere() throws {
        #expect(try command("j") == .next)
        #expect(try command("gg") == .first)
        #expect(try command("G") == .last)
        #expect(try command("a") == .tool(.arrow))
        #expect(try command("esc") == .tool(.select))
        #expect(try command("shift-left") == .nudge(.left, big: true))
        #expect(try command("cmd-]") == .bringForward)
        #expect(try command("cmd-[") == .sendBackward)
        #expect(try command("7") == .preset(7))
        #expect(try command("=") == .zoomFit)
        #expect(try command("0") == .zoomActual)
        #expect(try command("+") == .zoomIn)
        #expect(try command("-") == .zoomOut)
        #expect(try command("z") == .zoomArea)
        #expect(try command("cmd-z") == .undo)
        #expect(try command("cmd-Z") == .redo)
    }

    /// `[` and `]` are the sibling case, as in sView (SN-501), so z-order
    /// takes the modifier, as in Figma.
    @Test func bracketsAreTheSiblingCase() throws {
        #expect(try command("]") == .caseNext)
        #expect(try command("[") == .casePrevious)
        #expect(try command(":") == .commandLine)
    }

    /// Shift lives in a character's case (`G`, `cmd-Z`), so no two lines may
    /// parse to the same key: a later line would silently replace the
    /// earlier one, as `cmd-shift-z redo` once replaced `cmd-z undo`.
    @Test func noTwoLinesBindTheSameKeys() throws {
        let lines = KeyValueParser.parse(DefaultKeymap.text)
        let keys = try lines.map { try Key.parseSequence($0.key) }
        #expect(Set(keys).count == keys.count)
    }

    @Test func gWaitsForASecondKey() throws {
        var matcher = KeyMatcher(keymap: DefaultKeymap.keymap)
        #expect(matcher.feed(Key("g")) == .pending(display: "g"))
        #expect(matcher.feed(Key("g")) == .matched(Invocation(.first)))
    }

    @Test func toolsSwitchAndEscClearsTheSelectionSecond() throws {
        let item = Annotation(shape: .counter(at: .zero))
        var fixture = try EditorFixture(items: [item])
        #expect(try Command.parse("tool arrow") == .tool(.arrow))
        #expect(throws: CommandError.badArgument("tool needs one of: select, arrow, rectangle, ellipse, counter, text, highlight, blur, crop")) {
            try Command.parse("tool laser")
        }
        fixture.run(.selectAll)
        fixture.run(.tool(.arrow))
        #expect(fixture.state.tool == .arrow)
        fixture.run(.tool(.select))
        #expect(fixture.state.tool == .select)
        #expect(fixture.state.selection == [item.id])
        fixture.run(.tool(.select))
        #expect(fixture.state.selection.isEmpty)
        #expect(fixture.state.undo.count == 0)
    }
}
