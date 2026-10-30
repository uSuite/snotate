import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct TextToolTests {
    private let label = Annotation(shape: .text(at: CGPoint(x: 100, y: 100), text: "Start", pill: false, leader: nil))
    private let box = Annotation(shape: .rectangle(CGRect(x: 300, y: 100, width: 50, height: 50), fill: false))

    @Test func tPicksTheToolAndASecondPressSwitchesThePill() throws {
        #expect(DefaultKeymap.keymap.command(for: [Key("t")]) == .tool(.text))
        #expect(DefaultKeymap.keymap.command(for: [Key("enter")]) == .edit)
        var fixture = try EditorFixture()
        fixture.run(.tool(.text))
        #expect(fixture.run(.tool(.text)) == [.message("Text: pill")])
        #expect(fixture.run(.tool(.text)) == [.message("Text: plain")])
    }

    @Test func editOpensOnlyASingleSelectedText() throws {
        var fixture = try EditorFixture(items: [label, box])
        #expect(fixture.run(.edit).isEmpty)
        fixture.run(.select([label.id]))
        #expect(fixture.run(.edit) == [.beginTextEdit(label.id)])
        fixture.run(.select([box.id]))
        #expect(fixture.run(.edit).isEmpty)
        fixture.run(.selectAll)
        #expect(fixture.run(.edit).isEmpty)
        #expect(fixture.state.undo.count == 0)
    }

    @Test func fillSwitchesThePillOfSelectedText() throws {
        var fixture = try EditorFixture(items: [label, box])
        fixture.run(.selectAll)
        fixture.run(.fill)
        #expect(fixture.items.map(\.shape.fill) == [true, true])
        #expect(fixture.items[0].shape == .text(at: CGPoint(x: 100, y: 100), text: "Start", pill: true, leader: nil))
    }
}

struct TextGestureTests {
    private func newText(
        from start: CGPoint,
        to end: CGPoint,
        shift: Bool = false,
        snap: CGFloat? = nil,
        fixture: inout EditorFixture
    ) throws -> Annotation? {
        if fixture.state.tool != .text {
            fixture.run(.tool(.text))
        }
        var gesture = try #require(Gesture.begin(at: start, in: fixture.state, shift: shift, tolerance: 4, handleRadius: 8).gesture)
        gesture.drag(to: end, shift: shift, in: fixture.state, snapThreshold: snap)
        #expect(gesture.finish(in: fixture.state, minimumLength: 4).isEmpty)
        return gesture.newText(in: fixture.state, minimumLength: 4)
    }

    @Test func aClickStartsTextThereADragAddsALeaderToThePress() throws {
        var fixture = try EditorFixture()
        let click = try newText(from: CGPoint(x: 400, y: 450), to: CGPoint(x: 401, y: 451), fixture: &fixture)
        #expect(click?.shape == .text(at: CGPoint(x: 401, y: 451), text: "", pill: false, leader: nil))
        let drag = try newText(from: CGPoint(x: 762, y: 726), to: CGPoint(x: 1000, y: 560), fixture: &fixture)
        #expect(drag?.shape == .text(at: CGPoint(x: 1000, y: 560), text: "", pill: false, leader: CGPoint(x: 762, y: 726)))
    }

    @Test func newTextTakesThePillVariantAndSnaps() throws {
        var fixture = try EditorFixture()
        fixture.run(.tool(.text))
        fixture.run(.tool(.text))
        fixture.run(.preset(2))
        let text = try newText(from: CGPoint(x: 795, y: 300), to: CGPoint(x: 797, y: 300), snap: 6, fixture: &fixture)
        #expect(text?.shape == .text(at: CGPoint(x: 800, y: 300), text: "", pill: true, leader: nil))
        #expect(text?.preset == 2)
    }
}

struct TextEditTests {
    private let label = Annotation(shape: .text(at: CGPoint(x: 100, y: 100), text: "Start", pill: false, leader: nil))

    @Test func newTextIsOneAddWhenCommittedAndNothingWhenEmpty() throws {
        var fixture = try EditorFixture()
        var edit = TextEdit(new: Annotation(shape: .text(at: CGPoint(x: 10, y: 10), text: "", pill: false, leader: nil)))
        #expect(edit.update("B").isEmpty)
        #expect(edit.update("Bấm").isEmpty)
        #expect(edit.preview(in: fixture.state).last?.shape == .text(at: CGPoint(x: 10, y: 10), text: "Bấm", pill: false, leader: nil))
        #expect(fixture.items.isEmpty)
        for command in edit.commit() {
            fixture.run(command)
        }
        #expect(fixture.items.map(\.shape) == [.text(at: CGPoint(x: 10, y: 10), text: "Bấm", pill: false, leader: nil)])
        #expect(fixture.state.undo.count == 1)
        #expect(fixture.state.undo.undoLabel == "Add")
        var empty = TextEdit(new: Annotation(shape: .text(at: .zero, text: "", pill: false, leader: nil)))
        _ = empty.update("  \n ")
        #expect(empty.commit().isEmpty)
    }

    @Test func editingExistingTextIsLiveAndOneUndoEntry() throws {
        var fixture = try EditorFixture(items: [label])
        #expect(TextEdit(existing: UUID(), in: fixture.state) == nil)
        var edit = try #require(TextEdit(existing: label.id, in: fixture.state))
        #expect(edit.text == "Start")
        for text in ["Start ", "Start t", "Start the VM"] {
            for command in edit.update(text) {
                fixture.run(command)
            }
        }
        #expect(edit.update("Start the VM").isEmpty)
        #expect(fixture.items[0].shape == .text(at: CGPoint(x: 100, y: 100), text: "Start the VM", pill: false, leader: nil))
        #expect(edit.preview(in: fixture.state) == fixture.items)
        #expect(edit.commit() == [.endTextEdit])
        fixture.run(.endTextEdit)
        #expect(fixture.state.undo.count == 1)
        #expect(fixture.state.undo.undoLabel == "Edit Text")
        fixture.run(.undo)
        #expect(fixture.items[0].shape == label.shape)
    }

    @Test func emptyingExistingTextDeletesIt() throws {
        var fixture = try EditorFixture(items: [label])
        var edit = try #require(TextEdit(existing: label.id, in: fixture.state))
        for command in edit.update("") {
            fixture.run(command)
        }
        let commands = edit.commit()
        #expect(commands == [.select([label.id]), .delete])
        for command in commands {
            fixture.run(command)
        }
        #expect(fixture.items.isEmpty)
        fixture.run(.undo)
        fixture.run(.undo)
        #expect(fixture.items[0].shape == label.shape)
    }
}
