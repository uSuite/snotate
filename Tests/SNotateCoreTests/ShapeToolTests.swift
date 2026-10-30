import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct ShapeToolTests {
    private let outline = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 50, height: 50), fill: false))
    private let filled = Annotation(shape: .ellipse(CGRect(x: 300, y: 100, width: 50, height: 50), fill: true))
    private let counter = Annotation(shape: .counter(at: CGPoint(x: 500, y: 500)))

    @Test func aSecondPressSwitchesTheFillForNewShapes() throws {
        var fixture = try EditorFixture()
        #expect(fixture.run(.tool(.rectangle)).isEmpty)
        #expect(fixture.state.tool == .rectangle)
        #expect(fixture.run(.tool(.rectangle)) == [.message("Rectangle: filled")])
        #expect(fixture.state.filled == [.rectangle])
        fixture.run(.tool(.ellipse))
        #expect(fixture.run(.tool(.ellipse)) == [.message("Ellipse: filled")])
        #expect(fixture.run(.tool(.ellipse)) == [.message("Ellipse: outline")])
        #expect(fixture.state.filled == [.rectangle])
        fixture.run(.tool(.arrow))
        #expect(fixture.run(.tool(.arrow)).isEmpty)
        #expect(fixture.state.undo.count == 0)
    }

    @Test func fillSwitchesTheSelectedShapesTogether() throws {
        var fixture = try EditorFixture(items: [outline, filled, counter])
        fixture.run(.selectAll)
        #expect(fixture.run(.fill) == [.sidecarChanged])
        #expect(fixture.items.map(\.shape.fill) == [true, true, nil])
        #expect(fixture.state.undo.undoLabel == "Change Fill")
        fixture.run(.fill)
        #expect(fixture.items.map(\.shape.fill) == [false, false, nil])
        #expect(fixture.items[2] == counter)
        fixture.run(.select([counter.id]))
        #expect(fixture.run(.fill).isEmpty)
        #expect(fixture.state.undo.count == 2)
    }

    @Test func theKeysAreBound() throws {
        #expect(DefaultKeymap.keymap.command(for: [Key("r")]) == .tool(.rectangle))
        #expect(DefaultKeymap.keymap.command(for: [Key("e")]) == .tool(.ellipse))
        #expect(DefaultKeymap.keymap.command(for: [Key("f")]) == .fill)
    }
}
