import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct CommandTests {
    @Test func everyKeyableCommandRoundTripsThroughItsName() throws {
        for command in Command.keyable {
            let name = try #require(command.name)
            #expect(try Command.parse(name) == command)
        }
        #expect(Command.keyable.count == Set(Command.keyable.compactMap(\.name)).count)
    }

    @Test func namesUseTheKeymapSpelling() throws {
        #expect(try Command.parse("go-to 12") == .goTo(12))
        #expect(try Command.parse("nudge-left-10") == .nudge(.left, big: true))
        #expect(try Command.parse("  bring-forward  ") == .bringForward)
        #expect(try Command.parse("preset 3") == .preset(3))
        #expect(Command.undo.name == "undo")
        #expect(Command.nudge(.down, big: false).name == "nudge-down")
    }

    @Test func canvasCommandsHaveNoName() {
        let id = UUID()
        let canvas: [Command] = [
            .add(Annotation(shape: .counter(at: .zero))),
            .setShape(id, .counter(at: .zero)),
            .editText(id, "x"),
            .move([id], by: CGVector(dx: 1, dy: 1)),
            .select([id]),
            .toggleSelect(id),
            .setCrop(nil),
        ]
        #expect(canvas.allSatisfy { $0.name == nil })
    }

    @Test func badNamesAndArgumentsAreRefused() {
        let cases: [(String, CommandError)] = [
            ("zoom-sideways", .unknown("zoom-sideways")),
            ("", .unknown("")),
            ("go-to", .badArgument("go-to needs a step number")),
            ("go-to zero", .badArgument("go-to needs a step number")),
            ("go-to 0", .badArgument("go-to needs a step number")),
            ("preset 10", .badArgument("preset needs a number from 1 to 9")),
            ("delete now", .badArgument("delete takes no argument")),
        ]
        for (text, error) in cases {
            #expect(throws: error) {
                try Command.parse(text)
            }
        }
    }
}
