import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct GestureTests {
    private let box = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 100), fill: true))
    private let other = Annotation(shape: .rectangle(CGRect(x: 600, y: 100, width: 100, height: 100), fill: true))
    private let arrow = Annotation(shape: .arrow(from: CGPoint(x: 800, y: 600), to: CGPoint(x: 1000, y: 600), curve: nil), preset: 2)

    private func begin(
        _ fixture: inout EditorFixture,
        _ x: CGFloat,
        _ y: CGFloat,
        shift: Bool = false
    ) -> Gesture? {
        let (gesture, commands) = Gesture.begin(
            at: CGPoint(x: x, y: y),
            in: fixture.state,
            shift: shift,
            tolerance: 4,
            handleRadius: 8
        )
        for command in commands {
            fixture.run(command)
        }
        return gesture
    }

    private func finish(
        _ gesture: inout Gesture,
        _ fixture: inout EditorFixture,
        to x: CGFloat,
        _ y: CGFloat,
        shift: Bool = false,
        snap: CGFloat? = nil
    ) -> [Command] {
        gesture.drag(to: CGPoint(x: x, y: y), shift: shift, in: fixture.state, snapThreshold: snap)
        return gesture.finish(in: fixture.state, minimumLength: 4)
    }

    @Test func theArrowToolDrawsOneArrowInTheActivePreset() throws {
        var fixture = try EditorFixture()
        fixture.run(.tool(.arrow))
        fixture.run(.preset(3))
        var gesture = try #require(begin(&fixture, 100, 100))
        gesture.drag(to: CGPoint(x: 200, y: 150), shift: false, in: fixture.state, snapThreshold: nil)
        let preview = gesture.preview(in: fixture.state)
        #expect(preview.items.last?.shape == .arrow(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150), curve: nil))
        let commands = finish(&gesture, &fixture, to: 300, 200)
        guard case .add(let added) = commands.first, commands.count == 1 else {
            Issue.record("expected one add, got \(commands)")
            return
        }
        #expect(added.shape == .arrow(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200), curve: nil))
        #expect(added.preset == 3)
    }

    @Test func aTinyDragIsAClickAndDrawsNothing() throws {
        var fixture = try EditorFixture()
        fixture.run(.tool(.arrow))
        var gesture = try #require(begin(&fixture, 100, 100))
        #expect(finish(&gesture, &fixture, to: 102, 101).isEmpty)
    }

    @Test func shiftKeepsAnArrowAt45DegreesAndEndsSnap() throws {
        var fixture = try EditorFixture()
        fixture.run(.tool(.arrow))
        var gesture = try #require(begin(&fixture, 100, 100))
        gesture.drag(to: CGPoint(x: 300, y: 290), shift: true, in: fixture.state, snapThreshold: 6)
        guard case .arrow(_, let to, _) = gesture.preview(in: fixture.state).items.last?.shape else {
            Issue.record("no arrow preview")
            return
        }
        #expect(abs((to.x - 100) - (to.y - 100)) < 0.001)
        var snapped = try #require(begin(&fixture, 500, 500))
        let commands = finish(&snapped, &fixture, to: 1597, 498, snap: 6)
        guard case .add(let added) = commands.first, case .arrow(_, let end, _) = added.shape else {
            Issue.record("expected an arrow")
            return
        }
        #expect(end == CGPoint(x: 1600, y: 500))
        #expect(!snapped.guides.isEmpty)
    }

    @Test func clickingAnItemSelectsItAndDraggingMovesIt() throws {
        var fixture = try EditorFixture(items: [box, other])
        var gesture = try #require(begin(&fixture, 150, 150))
        #expect(fixture.state.selection == [box.id])
        gesture.drag(to: CGPoint(x: 170, y: 160), shift: false, in: fixture.state, snapThreshold: nil)
        #expect(gesture.preview(in: fixture.state).items[0].shape == .rectangle(CGRect(x: 120, y: 110, width: 200, height: 100), fill: true))
        let commands = finish(&gesture, &fixture, to: 175, 160)
        #expect(commands == [.move([box.id], by: CGVector(dx: 25, dy: 10))])
    }

    @Test func aMoveSnapsToTheOtherObjectAndShowsAGuide() throws {
        var fixture = try EditorFixture(items: [box, other])
        var gesture = try #require(begin(&fixture, 150, 150))
        // Bounds include half the stroke: the box's right edge (302) moved by
        // 299 lands at 601, three pixels past other's left edge (598).
        let commands = finish(&gesture, &fixture, to: 449, 150, snap: 6)
        #expect(commands == [.move([box.id], by: CGVector(dx: 296, dy: 0))])
        #expect(gesture.guides.contains(Snapper.Guide(axis: .x, position: 598)))
    }

    @Test func aClickWithoutMovingIsNotAMove() throws {
        var fixture = try EditorFixture(items: [box])
        var gesture = try #require(begin(&fixture, 150, 150))
        #expect(finish(&gesture, &fixture, to: 150, 150).isEmpty)
        #expect(fixture.state.selection == [box.id])
    }

    @Test func shiftClickTogglesAndMovesTheWholeSelection() throws {
        var fixture = try EditorFixture(items: [box, other])
        _ = begin(&fixture, 150, 150)
        var gesture = try #require(begin(&fixture, 650, 150, shift: true))
        #expect(fixture.state.selection == [box.id, other.id])
        #expect(finish(&gesture, &fixture, to: 660, 150) == [.move([box.id, other.id], by: CGVector(dx: 10, dy: 0))])
        #expect(begin(&fixture, 650, 150, shift: true) == nil)
        #expect(fixture.state.selection == [box.id])
    }

    @Test func aHandleOfTheSelectedItemReshapesIt() throws {
        var fixture = try EditorFixture(items: [arrow])
        fixture.run(.select([arrow.id]))
        var end = try #require(begin(&fixture, 1003, 602))
        #expect(finish(&end, &fixture, to: 1000, 700) == [.setShape(arrow.id, .arrow(from: CGPoint(x: 800, y: 600), to: CGPoint(x: 1000, y: 700), curve: nil))])
        var bend = try #require(begin(&fixture, 900, 600))
        #expect(finish(&bend, &fixture, to: 900, 500) == [.setShape(arrow.id, .arrow(from: CGPoint(x: 800, y: 600), to: CGPoint(x: 1000, y: 600), curve: CGPoint(x: 900, y: 500)))])
    }

    @Test func emptySpaceStartsAMarquee() throws {
        var fixture = try EditorFixture(items: [box, other, arrow])
        var gesture = try #require(begin(&fixture, 50, 50))
        gesture.drag(to: CGPoint(x: 650, y: 120), shift: false, in: fixture.state, snapThreshold: nil)
        #expect(gesture.preview(in: fixture.state).marquee == CGRect(x: 50, y: 50, width: 600, height: 70))
        #expect(gesture.finish(in: fixture.state, minimumLength: 4) == [.select([box.id, other.id])])
        fixture.run(.select([arrow.id]))
        var additive = try #require(begin(&fixture, 50, 50, shift: true))
        #expect(finish(&additive, &fixture, to: 160, 160) == [.select([arrow.id, box.id])])
        var click = try #require(begin(&fixture, 50, 50))
        #expect(finish(&click, &fixture, to: 50, 50) == [.select([])])
    }
}
