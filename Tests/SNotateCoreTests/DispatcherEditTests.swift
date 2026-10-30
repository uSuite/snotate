import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct DispatcherEditTests {
    private let a = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))
    private let b = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 50, height: 50), fill: false))
    private let c = Annotation(shape: .text(at: CGPoint(x: 300, y: 300), text: "Start", pill: false, leader: nil))

    @Test func addPutsItOnTopSelectsItAndUndoes() throws {
        var fixture = try EditorFixture(items: [a])
        let before = fixture.state.document.sidecar
        #expect(fixture.run(.add(b)) == [.sidecarChanged])
        #expect(fixture.items.map(\.id) == [a.id, b.id])
        #expect(fixture.state.selection == [b.id])
        #expect(fixture.state.undo.undoLabel == "Add")
        #expect(fixture.run(.undo) == [.sidecarChanged])
        #expect(fixture.state.document.sidecar == before)
        #expect(fixture.state.selection.isEmpty)
        fixture.run(.redo)
        #expect(fixture.items.map(\.id) == [a.id, b.id])
        #expect(fixture.state.selection == [b.id])
    }

    @Test func setShapeChangesOneItemAndANoOpPushesNothing() throws {
        var fixture = try EditorFixture(items: [a, b])
        let moved = Shape.counter(at: CGPoint(x: 20, y: 30))
        fixture.run(.setShape(a.id, moved))
        #expect(fixture.items[0].shape == moved)
        #expect(fixture.items[0].id == a.id)
        #expect(fixture.run(.setShape(a.id, moved)).isEmpty)
        #expect(fixture.run(.setShape(UUID(), moved)).isEmpty)
        #expect(fixture.state.undo.count == 1)
    }

    @Test func typingIsOneUndoEntryUntilTheEditEnds() throws {
        var fixture = try EditorFixture(items: [c])
        fixture.run(.editText(c.id, "Start t"))
        fixture.run(.editText(c.id, "Start th"))
        fixture.run(.editText(c.id, "Start the VM"))
        #expect(fixture.state.undo.count == 1)
        fixture.run(.endTextEdit)
        fixture.run(.editText(c.id, "Start the VM now"))
        #expect(fixture.state.undo.count == 2)
        fixture.run(.undo)
        fixture.run(.undo)
        #expect(fixture.items[0].shape == c.shape)
        #expect(fixture.run(.editText(a.id, "not text")).isEmpty)
    }

    @Test func moveAndNudgeShiftTheSelection() throws {
        var fixture = try EditorFixture(items: [a, b])
        fixture.run(.move([a.id, b.id], by: CGVector(dx: 5, dy: -5)))
        #expect(fixture.items[0].shape == .counter(at: CGPoint(x: 15, y: 5)))
        #expect(fixture.run(.nudge(.right, big: false)) == [.pan(.right, big: false)])
        fixture.run(.select([a.id]))
        fixture.run(.nudge(.right, big: false))
        fixture.run(.nudge(.down, big: true), count: 2)
        #expect(fixture.items[0].shape == .counter(at: CGPoint(x: 16, y: 25)))
        #expect(fixture.items[1].shape == .rectangle(CGRect(x: 105, y: 95, width: 50, height: 50), fill: false))
        #expect(fixture.state.undo.undoLabel == "Nudge")
        #expect(fixture.state.undo.count == 3)
    }

    @Test func aNudgeIsOneImagePixelOnAScaledStep() throws {
        var fixture = try EditorFixture(fixture: "poc-sample-vm-scale")
        fixture.state.document.sidecar.steps[1].size = PixelSize(width: 1600, height: 1000)
        fixture.state.document.sidecar.steps[1].items = [a]
        fixture.run(.next)
        #expect(fixture.state.currentStep?.scale == .scaled(2))
        fixture.run(.selectAll)
        fixture.run(.nudge(.left, big: false))
        #expect(fixture.items[0].shape == .counter(at: CGPoint(x: 9.5, y: 10)))
    }

    @Test func deleteRemovesTheSelectionAndUndoBringsItBack() throws {
        var fixture = try EditorFixture(items: [a, b, c])
        fixture.run(.select([a.id, c.id]))
        fixture.run(.delete)
        #expect(fixture.items.map(\.id) == [b.id])
        #expect(fixture.state.selection.isEmpty)
        fixture.run(.undo)
        #expect(fixture.items.map(\.id) == [a.id, b.id, c.id])
        #expect(fixture.state.selection == [a.id, c.id])
        fixture.run(.deselect)
        #expect(fixture.run(.delete).isEmpty)
    }

    @Test func duplicateAddsOffsetCopiesOnTopAndSelectsThem() throws {
        var fixture = try EditorFixture(items: [a, b])
        fixture.run(.selectAll)
        fixture.run(.duplicate)
        #expect(fixture.items.count == 4)
        let copies = Array(fixture.items[2...])
        #expect(Set(copies.map(\.id)).isDisjoint(with: [a.id, b.id]))
        #expect(fixture.state.selection == Set(copies.map(\.id)))
        #expect(copies[0].shape == .counter(at: CGPoint(x: 20, y: 20)))
        #expect(copies[1].shape == .rectangle(CGRect(x: 110, y: 110, width: 50, height: 50), fill: false))
    }

    @Test func zOrderMovesOnePlacePerCount() throws {
        var fixture = try EditorFixture(items: [a, b, c])
        fixture.run(.select([a.id]))
        fixture.run(.bringForward)
        #expect(fixture.items.map(\.id) == [b.id, a.id, c.id])
        fixture.run(.bringForward, count: 5)
        #expect(fixture.items.map(\.id) == [b.id, c.id, a.id])
        #expect(fixture.run(.bringForward).isEmpty)
        fixture.run(.select([a.id, c.id]))
        fixture.run(.sendBackward)
        #expect(fixture.items.map(\.id) == [c.id, a.id, b.id])
        #expect(fixture.run(.sendBackward).isEmpty)
    }

    @Test func presetChangesTheSelectionOrTheOneForNewItems() throws {
        var fixture = try EditorFixture(items: [a, b])
        #expect(fixture.run(.preset(3)).isEmpty)
        #expect(fixture.state.activePreset == 3)
        #expect(fixture.state.undo.count == 0)
        fixture.run(.select([b.id]))
        fixture.run(.preset(2))
        #expect(fixture.items.map(\.preset) == [1, 2])
        #expect(fixture.state.activePreset == 3)
        #expect(fixture.state.undo.undoLabel == "Change Preset")
    }

    @Test func undoReturnsToTheStepOfTheChange() throws {
        var fixture = try EditorFixture()
        fixture.run(.add(a))
        fixture.run(.goTo(3))
        fixture.run(.undo)
        #expect(fixture.state.current == 0)
        #expect(fixture.items.isEmpty)
        #expect(fixture.run(.undo).isEmpty)
        fixture.run(.goTo(5))
        fixture.run(.redo)
        #expect(fixture.state.current == 0)
        #expect(fixture.items.map(\.id) == [a.id])
    }
}

struct ExcludeTests {
    @Test func xTogglesTheStepAndSaysWhichWay() throws {
        var fixture = try EditorFixture()
        #expect(DefaultKeymap.keymap.command(for: [Key("x")]) == .exclude)
        #expect(fixture.run(.exclude) == [.sidecarChanged, .message("Step excluded from export")])
        #expect(fixture.state.currentStep?.excluded == true)
        #expect(fixture.run(.exclude) == [.sidecarChanged, .message("Step included again")])
        #expect(fixture.state.currentStep?.excluded == false)
        fixture.run(.exclude)
        fixture.run(.undo)
        #expect(fixture.state.currentStep?.excluded == false)
    }

    @Test func theExcludedFilesAreListed() throws {
        var fixture = try EditorFixture()
        #expect(fixture.run(.listExcluded) == [.listExcluded([])])
        fixture.run(.next)
        fixture.run(.exclude)
        fixture.run(.last)
        fixture.run(.exclude)
        #expect(fixture.run(.listExcluded) == [.listExcluded(["poc-sample-vm-migrate-01.png", "poc-sample-vm-migrate-05.png"])])
        #expect(try Command.parseCommandLine("excluded") == .listExcluded)
    }
}
