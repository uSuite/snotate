import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct DispatcherViewTests {
    private let box = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 100), fill: true))

    @Test func zoomCommandsAskTheCanvasAndChangeNothing() throws {
        var fixture = try EditorFixture(items: [box])
        let sidecar = fixture.state.document.sidecar
        #expect(fixture.run(.zoomIn) == [.zoom(.steps(1))])
        #expect(fixture.run(.zoomOut, count: 3) == [.zoom(.steps(-3))])
        #expect(fixture.run(.zoomFit) == [.zoom(.fit)])
        #expect(fixture.run(.zoomActual) == [.zoom(.actual)])
        #expect(fixture.state.document.sidecar == sidecar)
        #expect(fixture.state.undo.count == 0)
    }

    @Test func arrowKeysPanWithNothingSelectedAndNudgeOtherwise() throws {
        var fixture = try EditorFixture(items: [box])
        #expect(fixture.run(.nudge(.left, big: true)) == [.pan(.left, big: true)])
        fixture.run(.select([box.id]))
        #expect(fixture.run(.nudge(.left, big: false)) == [.sidecarChanged])
        #expect(fixture.items[0].shape == .rectangle(CGRect(x: 99, y: 100, width: 200, height: 100), fill: true))
    }

    @Test func zoomAreaArmsOneDragAndAnyOtherCommandDisarms() throws {
        var fixture = try EditorFixture(items: [box])
        fixture.run(.tool(.arrow))
        #expect(fixture.run(.zoomArea).isEmpty)
        #expect(fixture.state.zoomArmed)
        fixture.run(.zoomArea)
        #expect(!fixture.state.zoomArmed)
        fixture.run(.zoomArea)
        fixture.run(.tool(.select))
        #expect(!fixture.state.zoomArmed)
        fixture.run(.zoomArea)
        let area = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(fixture.run(.zoomTo(area)) == [.zoom(.area(area))])
        #expect(!fixture.state.zoomArmed)
        #expect(fixture.run(.zoomTo(CGRect(x: 40, y: 50, width: 0, height: 0))) == [.zoom(.inAt(CGPoint(x: 40, y: 50)))])
    }

    @Test func anArmedDragZoomsInsteadOfUsingTheTool() throws {
        var fixture = try EditorFixture(items: [box])
        fixture.run(.tool(.rectangle))
        fixture.run(.zoomArea)
        var (gesture, commands) = Gesture.begin(at: CGPoint(x: 150, y: 150), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8)
        #expect(commands.isEmpty)
        gesture?.drag(to: CGPoint(x: 450, y: 350), shift: false, in: fixture.state, snapThreshold: 6)
        #expect(gesture?.preview(in: fixture.state).marquee == CGRect(x: 150, y: 150, width: 300, height: 200))
        #expect(gesture?.finish(in: fixture.state, minimumLength: 4) == [.zoomTo(CGRect(x: 150, y: 150, width: 300, height: 200))])
        var click = Gesture.begin(at: CGPoint(x: 150, y: 150), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8).gesture
        click?.drag(to: CGPoint(x: 151, y: 150), shift: false, in: fixture.state, snapThreshold: nil)
        #expect(click?.finish(in: fixture.state, minimumLength: 4) == [.zoomTo(CGRect(x: 150, y: 150, width: 0, height: 0))])
        fixture.run(.zoomArea)
        #expect(Gesture.begin(at: CGPoint(x: 150, y: 150), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8).gesture?.kind == .draw(.rectangle))
    }
}
