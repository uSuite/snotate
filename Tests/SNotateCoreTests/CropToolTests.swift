import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct CropToolTests {
    private let card = CGRect(x: 320, y: 140, width: 1220, height: 740)

    private func crop(_ fixture: EditorFixture, _ step: Int) -> CGRect? {
        fixture.state.document.sidecar.steps[step].crop
    }

    @Test func cPicksTheToolWithoutAVariant() throws {
        #expect(DefaultKeymap.keymap.command(for: [Key("c")]) == .tool(.crop))
        #expect(DefaultKeymap.keymap.command(for: [Key("C")]) == .cropPrevious)
        #expect(!Tool.crop.fills)
        var fixture = try EditorFixture()
        fixture.run(.tool(.crop))
        #expect(fixture.run(.tool(.crop)).isEmpty)
        #expect(fixture.state.tool == .crop)
    }

    @Test func sameAsPreviousCopiesTheNearestEarlierCrop() throws {
        var fixture = try EditorFixture()
        #expect(fixture.run(.cropPrevious) == [.message("No earlier step has a crop")])
        fixture.run(.setCrop(card))
        fixture.run(.goTo(3))
        #expect(fixture.run(.cropPrevious) == [.sidecarChanged])
        #expect(crop(fixture, 2) == card)
        #expect(crop(fixture, 1) == nil)
        #expect(fixture.state.undo.undoLabel == "Crop")
        fixture.run(.setCrop(CGRect(x: 0, y: 64, width: 1600, height: 936)))
        fixture.run(.next)
        fixture.run(.cropPrevious)
        #expect(crop(fixture, 3) == CGRect(x: 0, y: 64, width: 1600, height: 936))
    }

    @Test func deleteClearsTheCropOnlyWithTheCropTool() throws {
        let item = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))
        var fixture = try EditorFixture(items: [item])
        fixture.run(.setCrop(card))
        fixture.run(.selectAll)
        fixture.run(.tool(.crop))
        fixture.run(.delete)
        #expect(crop(fixture, 0) == nil)
        #expect(fixture.items.count == 1)
        #expect(fixture.state.undo.undoLabel == "Remove Crop")
        #expect(fixture.run(.delete).isEmpty)
        fixture.run(.tool(.select))
        fixture.run(.selectAll)
        fixture.run(.delete)
        #expect(fixture.items.isEmpty)
    }
}

struct CropGestureTests {
    private let card = CGRect(x: 320, y: 140, width: 1220, height: 740)

    private func crop(
        from start: CGPoint,
        to end: CGPoint,
        shift: Bool = false,
        option: Bool = false,
        snap: CGFloat? = nil,
        fixture: EditorFixture
    ) throws -> (Gesture, [Command]) {
        var gesture = try #require(Gesture.begin(at: start, in: fixture.state, shift: shift, tolerance: 4, handleRadius: 8).gesture)
        gesture.drag(to: end, shift: shift, option: option, in: fixture.state, snapThreshold: snap)
        return (gesture, gesture.finish(in: fixture.state, minimumLength: 4))
    }

    @Test func aDragDrawsANewCropAndShiftLocksTheImageAspect() throws {
        var fixture = try EditorFixture()
        fixture.run(.tool(.crop))
        let (gesture, commands) = try crop(from: CGPoint(x: 320, y: 140), to: CGPoint(x: 1540, y: 880), fixture: fixture)
        #expect(gesture.kind == .cropDraw)
        #expect(commands == [.setCrop(card)])
        #expect(gesture.preview(in: fixture.state).crop == card)
        #expect(try crop(from: .zero, to: CGPoint(x: 800, y: 100), shift: true, fixture: fixture).1 == [.setCrop(CGRect(x: 0, y: 0, width: 800, height: 500))])
        #expect(try crop(from: CGPoint(x: 1400, y: 800), to: CGPoint(x: 1597, y: 997), snap: 6, fixture: fixture).1 == [.setCrop(CGRect(x: 1400, y: 800, width: 200, height: 200))])
        #expect(try crop(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 300), fixture: fixture).1.isEmpty)
    }

    @Test func insideTheCropMovesItAndHandlesResizeIt() throws {
        var fixture = try EditorFixture()
        fixture.run(.setCrop(card))
        fixture.run(.tool(.crop))
        let (move, moved) = try crop(from: CGPoint(x: 900, y: 500), to: CGPoint(x: 910, y: 480), fixture: fixture)
        #expect(move.kind == .cropMove(card))
        #expect(moved == [.setCrop(card.offsetBy(dx: 10, dy: -20))])
        #expect(try crop(from: CGPoint(x: 900, y: 500), to: CGPoint(x: 901, y: 500), fixture: fixture).1.isEmpty)
        let (handle, resized) = try crop(from: CGPoint(x: 1540, y: 880), to: CGPoint(x: 1500, y: 860), fixture: fixture)
        #expect(handle.kind == .cropHandle(.bottomRight, card))
        #expect(resized == [.setCrop(CGRect(x: 320, y: 140, width: 1180, height: 720))])
        let (_, kept) = try crop(from: CGPoint(x: 1540, y: 880), to: CGPoint(x: 1300, y: 860), shift: true, fixture: fixture)
        guard case .setCrop(let rect?) = kept.first else {
            Issue.record("expected a crop")
            return
        }
        #expect(abs(rect.width / rect.height - card.width / card.height) < 0.001)
        // Outside the crop a press draws a new one.
        #expect(try crop(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200), fixture: fixture).0.kind == .cropDraw)
    }

    @Test func aCropThatEndsOutsideTheImageIsClamped() throws {
        var fixture = try EditorFixture()
        fixture.run(.tool(.crop))
        for command in try crop(from: CGPoint(x: 1400, y: 800), to: CGPoint(x: 1800, y: 1200), fixture: fixture).1 {
            fixture.run(command)
        }
        #expect(fixture.state.document.sidecar.steps[0].crop == CGRect(x: 1400, y: 800, width: 200, height: 200))
    }
}
