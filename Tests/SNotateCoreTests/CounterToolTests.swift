import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct CounterToolTests {
    @Test func nPicksTheToolAndShiftNRestartsTheStep() throws {
        #expect(DefaultKeymap.keymap.command(for: [Key("n")]) == .tool(.counter))
        #expect(DefaultKeymap.keymap.command(for: [Key("N")]) == .restartCounter)
        var fixture = try EditorFixture()
        fixture.run(.tool(.counter))
        #expect(fixture.run(.tool(.counter)).isEmpty)
        #expect(fixture.state.tool == .counter)
        #expect(fixture.run(.restartCounter) == [.sidecarChanged, .message("Counters restart at 1 on this step")])
        #expect(fixture.run(.restartCounter) == [.sidecarChanged, .message("Counters continue on this step")])
        #expect(fixture.state.undo.count == 2)
    }
}

struct CounterGestureTests {
    private func place(
        from start: CGPoint,
        to end: CGPoint,
        shift: Bool = false,
        snap: CGFloat? = nil,
        fixture: inout EditorFixture
    ) throws -> (Gesture, [Command]) {
        if fixture.state.tool != .counter {
            fixture.run(.tool(.counter))
        }
        var gesture = try #require(Gesture.begin(at: start, in: fixture.state, shift: shift, tolerance: 4, handleRadius: 8).gesture)
        gesture.drag(to: end, shift: shift, in: fixture.state, snapThreshold: snap)
        return (gesture, gesture.finish(in: fixture.state, minimumLength: 4))
    }

    private func placed(_ commands: [Command]) -> Shape? {
        guard commands.count == 1, case .add(let annotation) = commands[0] else {
            return nil
        }
        return annotation.shape
    }

    @Test func aClickPlacesACounterWhereItIsReleased() throws {
        var fixture = try EditorFixture()
        let point = CGPoint(x: 392, y: 726)
        #expect(placed(try place(from: point, to: point, fixture: &fixture).1) == .counter(at: point))
        #expect(placed(try place(from: point, to: CGPoint(x: 420, y: 700), fixture: &fixture).1) == .counter(at: CGPoint(x: 420, y: 700)))
    }

    @Test func theCentreSnapsUnlessShifted() throws {
        var fixture = try EditorFixture()
        #expect(placed(try place(from: CGPoint(x: 795, y: 300), to: CGPoint(x: 797, y: 300), snap: 6, fixture: &fixture).1) == .counter(at: CGPoint(x: 800, y: 300)))
        #expect(placed(try place(from: CGPoint(x: 795, y: 300), to: CGPoint(x: 797, y: 300), shift: true, snap: 6, fixture: &fixture).1) == .counter(at: CGPoint(x: 797, y: 300)))
    }

    @Test func thePreviewShowsTheNumberItWillGetAndRenumbersLaterSteps() throws {
        let first = Annotation(shape: .counter(at: CGPoint(x: 100, y: 100)))
        let later = Annotation(shape: .counter(at: CGPoint(x: 100, y: 100)))
        var fixture = try EditorFixture(items: [first])
        fixture.state.document.sidecar.steps[2].items = [later]
        #expect(fixture.state.counterNumbers(items: fixture.state.items) == [first.id: 1, later.id: 2])
        fixture.run(.tool(.counter))
        var gesture = try #require(Gesture.begin(at: CGPoint(x: 300, y: 300), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8).gesture)
        gesture.drag(to: CGPoint(x: 310, y: 300), shift: false, in: fixture.state, snapThreshold: nil)
        let items = gesture.preview(in: fixture.state).items
        let numbers = fixture.state.counterNumbers(items: items)
        #expect(numbers[items[1].id] == 2)
        #expect(numbers[later.id] == 3)
    }
}
