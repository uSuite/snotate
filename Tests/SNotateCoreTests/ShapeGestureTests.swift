import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct ShapeGestureTests {
    private func draw(
        _ tool: Tool,
        from start: CGPoint,
        to end: CGPoint,
        shift: Bool = false,
        option: Bool = false,
        snap: CGFloat? = nil,
        fixture: inout EditorFixture
    ) throws -> [Command] {
        if fixture.state.tool != tool {
            fixture.run(.tool(tool))
        }
        var gesture = try #require(Gesture.begin(at: start, in: fixture.state, shift: shift, tolerance: 4, handleRadius: 8).gesture)
        gesture.drag(to: end, shift: shift, option: option, in: fixture.state, snapThreshold: snap)
        return gesture.finish(in: fixture.state, minimumLength: 4)
    }

    private func drawn(_ commands: [Command]) -> Shape? {
        guard commands.count == 1, case .add(let annotation) = commands[0] else {
            return nil
        }
        return annotation.shape
    }

    @Test func cornerToCornerInEitherDirection() throws {
        var fixture = try EditorFixture()
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(drawn(try draw(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200), fixture: &fixture)) == .rectangle(rect, fill: false))
        #expect(drawn(try draw(.rectangle, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 100), fixture: &fixture)) == .rectangle(rect, fill: false))
        #expect(drawn(try draw(.ellipse, from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 100), fixture: &fixture)) == .ellipse(rect, fill: false))
    }

    @Test func theFillVariantAppliesToNewShapes() throws {
        var fixture = try EditorFixture()
        fixture.run(.tool(.ellipse))
        fixture.run(.tool(.ellipse))
        let shape = drawn(try draw(.ellipse, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150), fixture: &fixture))
        #expect(shape == .ellipse(CGRect(x: 100, y: 100, width: 100, height: 50), fill: true))
    }

    @Test func shiftMakesASquareOptionDrawsFromTheCentre() throws {
        var fixture = try EditorFixture()
        let centre = CGPoint(x: 200, y: 200)
        #expect(drawn(try draw(.rectangle, from: centre, to: CGPoint(x: 400, y: 260), shift: true, fixture: &fixture))
            == .rectangle(CGRect(x: 200, y: 200, width: 200, height: 200), fill: false))
        #expect(drawn(try draw(.rectangle, from: centre, to: CGPoint(x: 140, y: 230), shift: true, fixture: &fixture))
            == .rectangle(CGRect(x: 140, y: 200, width: 60, height: 60), fill: false))
        #expect(drawn(try draw(.ellipse, from: centre, to: CGPoint(x: 260, y: 230), option: true, fixture: &fixture))
            == .ellipse(CGRect(x: 140, y: 170, width: 120, height: 60), fill: false))
        #expect(drawn(try draw(.ellipse, from: centre, to: CGPoint(x: 260, y: 230), shift: true, option: true, fixture: &fixture))
            == .ellipse(CGRect(x: 140, y: 140, width: 120, height: 120), fill: false))
    }

    @Test func aThinDragIsAClick() throws {
        var fixture = try EditorFixture()
        #expect(try draw(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 102), fixture: &fixture).isEmpty)
        #expect(try draw(.ellipse, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 103, y: 300), fixture: &fixture).isEmpty)
    }

    @Test func theDraggedCornerSnapsUnlessShifted() throws {
        var fixture = try EditorFixture()
        #expect(drawn(try draw(.rectangle, from: CGPoint(x: 1400, y: 800), to: CGPoint(x: 1597, y: 997), snap: 6, fixture: &fixture))
            == .rectangle(CGRect(x: 1400, y: 800, width: 200, height: 200), fill: false))
        #expect(drawn(try draw(.rectangle, from: CGPoint(x: 1400, y: 800), to: CGPoint(x: 1597, y: 990), shift: true, snap: 6, fixture: &fixture))
            == .rectangle(CGRect(x: 1400, y: 800, width: 197, height: 197), fill: false))
    }

    @Test func aDrawnCornerMeetsAnotherShapesCornerExactly() throws {
        let box = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 100), fill: false))
        var fixture = try EditorFixture(items: [box])
        // Snapped to the other rectangle's geometry, not its stroke's outer
        // edge two pixels further out.
        #expect(drawn(try draw(.rectangle, from: CGPoint(x: 400, y: 120), to: CGPoint(x: 498, y: 203), snap: 6, fixture: &fixture))
            == .rectangle(CGRect(x: 400, y: 120, width: 98, height: 80), fill: false))
        // A moved shape still snaps by its bounds, outer edge to outer edge.
        #expect(Snapper.targets(in: [box], excluding: [], styles: .builtIn) == [CGRect(x: 98, y: 98, width: 204, height: 104)])
        #expect(Snapper.targets(in: [box], excluding: [], styles: .builtIn, outlines: true) == [CGRect(x: 100, y: 100, width: 200, height: 100)])
    }

    @Test func optionResizesAboutTheCentreFromAHandle() throws {
        let box = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 100), fill: false))
        var fixture = try EditorFixture(items: [box])
        fixture.run(.select([box.id]))
        var gesture = try #require(Gesture.begin(at: CGPoint(x: 300, y: 200), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8).gesture)
        #expect(gesture.kind == .handle(box.id, .bottomRight))
        gesture.drag(to: CGPoint(x: 350, y: 220), shift: false, option: true, in: fixture.state, snapThreshold: nil)
        #expect(gesture.finish(in: fixture.state, minimumLength: 4) == [.setShape(box.id, .rectangle(CGRect(x: 50, y: 80, width: 300, height: 140), fill: false))])
    }
}

struct ClickThresholdTests {
    @Test func aClickNearASnapTargetDrawsNothing() throws {
        var fixture = try EditorFixture()
        for tool in [Tool.arrow, .rectangle, .ellipse] {
            fixture.run(.tool(tool))
            // The pointer moves 1 pixel, but the end snaps 10 pixels to the
            // image's centre line at x 800.
            var gesture = try #require(Gesture.begin(at: CGPoint(x: 790, y: 300), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8).gesture)
            gesture.drag(to: CGPoint(x: 791, y: 301), shift: false, in: fixture.state, snapThreshold: 12)
            #expect(gesture.finish(in: fixture.state, minimumLength: 4).isEmpty, "\(tool)")
        }
    }
}

struct ClickDoesNotMoveTests {
    /// A click to select a shape near a snap target must not move it, nor
    /// may a click on a handle reshape it.
    @Test func aClickOnAShapeOrAHandleChangesNothing() throws {
        let region = Annotation(shape: .blur(CGRect(x: 300, y: 12, width: 150, height: 40), pixelate: false))
        var fixture = try EditorFixture(items: [region])
        let (press, commands) = Gesture.begin(at: CGPoint(x: 375, y: 30), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8)
        var gesture = try #require(press)
        commands.forEach { fixture.run($0) }
        gesture.drag(to: CGPoint(x: 376, y: 31), shift: false, in: fixture.state, snapThreshold: 12)
        #expect(gesture.finish(in: fixture.state, minimumLength: 4).isEmpty)
        var handle = try #require(Gesture.begin(at: CGPoint(x: 450, y: 52), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8).gesture)
        #expect(handle.kind == .handle(region.id, .bottomRight))
        handle.drag(to: CGPoint(x: 451, y: 52), shift: false, in: fixture.state, snapThreshold: 12)
        #expect(handle.finish(in: fixture.state, minimumLength: 4).isEmpty)
    }
}
