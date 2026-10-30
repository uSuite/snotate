import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct HandleTests {
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    private func drag(
        _ handle: Handle,
        _ x: CGFloat,
        _ y: CGFloat,
        constrain: Bool = false,
        fromCentre: Bool = false
    ) -> CGRect {
        Geometry.resized(rect, handle: handle, to: CGPoint(x: x, y: y), constrain: constrain, fromCentre: fromCentre)
    }

    @Test func rectangleLikeShapesHaveEightHandles() {
        let handles = Geometry.handles(of: .blur(rect, pixelate: false))
        #expect(handles.map(\.handle) == [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left])
        #expect(handles[0].point == CGPoint(x: 100, y: 100))
        #expect(handles[4].point == CGPoint(x: 300, y: 200))
        #expect(handles[7].point == CGPoint(x: 100, y: 150))
    }

    @Test func arrowsCountersTextAndUnknownItems() {
        let straight = Geometry.handles(of: .arrow(from: .zero, to: CGPoint(x: 100, y: 0), curve: nil))
        #expect(straight.map(\.handle) == [.start, .end, .curve])
        #expect(straight[2].point == CGPoint(x: 50, y: 0))
        #expect(Geometry.handles(of: .counter(at: .zero)).isEmpty)
        #expect(Geometry.handles(of: .text(at: .zero, text: "x", pill: false, leader: nil)).isEmpty)
        #expect(Geometry.handles(of: .text(at: .zero, text: "x", pill: false, leader: CGPoint(x: 9, y: 9))).map(\.handle) == [.leader])
        #expect(Geometry.handles(of: .unknown(.null, reason: "x")).isEmpty)
    }

    @Test func cornersAndEdgesMoveOnlyTheirSides() {
        #expect(drag(.bottomRight, 400, 250) == CGRect(x: 100, y: 100, width: 300, height: 150))
        #expect(drag(.topLeft, 50, 80) == CGRect(x: 50, y: 80, width: 250, height: 120))
        #expect(drag(.top, 999, 60) == CGRect(x: 100, y: 60, width: 200, height: 140))
        #expect(drag(.left, 150, 999) == CGRect(x: 150, y: 100, width: 150, height: 100))
    }

    @Test func draggingPastTheOppositeSideFlips() {
        #expect(drag(.bottomRight, 50, 150) == CGRect(x: 50, y: 100, width: 50, height: 50))
        #expect(drag(.right, 40, 0) == CGRect(x: 40, y: 100, width: 60, height: 100))
    }

    @Test func shiftKeepsTheAspectRatio() {
        // Aspect 2:1; the larger of the two moves wins.
        #expect(drag(.bottomRight, 500, 210, constrain: true) == CGRect(x: 100, y: 100, width: 400, height: 200))
        #expect(drag(.bottomRight, 310, 400, constrain: true) == CGRect(x: 100, y: 100, width: 600, height: 300))
        #expect(drag(.topLeft, 0, 99, constrain: true) == CGRect(x: 0, y: 50, width: 300, height: 150))
    }

    @Test func optionResizesAboutTheCentre() {
        #expect(drag(.bottomRight, 350, 220, fromCentre: true) == CGRect(x: 50, y: 80, width: 300, height: 140))
        #expect(drag(.top, 0, 90, fromCentre: true) == CGRect(x: 100, y: 90, width: 200, height: 120))
        #expect(drag(.bottomRight, 400, 220, constrain: true, fromCentre: true) == CGRect(x: 0, y: 50, width: 400, height: 200))
    }

    @Test func arrowEndsCurveAndLeaderFollowTheirHandle() {
        let arrow = Shape.arrow(from: .zero, to: CGPoint(x: 100, y: 0), curve: nil)
        #expect(Geometry.dragging(arrow, handle: .end, to: CGPoint(x: 80, y: 30), constrain: false, fromCentre: false)
            == .arrow(from: .zero, to: CGPoint(x: 80, y: 30), curve: nil))
        #expect(Geometry.dragging(arrow, handle: .curve, to: CGPoint(x: 50, y: 40), constrain: false, fromCentre: false)
            == .arrow(from: .zero, to: CGPoint(x: 100, y: 0), curve: CGPoint(x: 50, y: 40)))
        let text = Shape.text(at: .zero, text: "x", pill: true, leader: CGPoint(x: 1, y: 1))
        #expect(Geometry.dragging(text, handle: .leader, to: CGPoint(x: 5, y: 6), constrain: false, fromCentre: false)
            == .text(at: .zero, text: "x", pill: true, leader: CGPoint(x: 5, y: 6)))
        #expect(Geometry.dragging(.counter(at: .zero), handle: .end, to: CGPoint(x: 5, y: 6), constrain: false, fromCentre: false)
            == .counter(at: .zero))
    }

    @Test func shiftSnapsAnArrowTo45Degrees() {
        let arrow = Shape.arrow(from: .zero, to: CGPoint(x: 100, y: 0), curve: nil)
        guard case .arrow(_, let to, _) = Geometry.dragging(arrow, handle: .end, to: CGPoint(x: 100, y: 90), constrain: true, fromCentre: false) else {
            Issue.record("not an arrow")
            return
        }
        #expect(abs(to.x - to.y) < 0.001)
        #expect(abs(hypot(to.x, to.y) - hypot(100, 90)) < 0.001)
    }

    @Test func movingShiftsEveryPoint() {
        let offset = CGVector(dx: 10, dy: -5)
        #expect(Geometry.moved(.arrow(from: .zero, to: CGPoint(x: 1, y: 1), curve: CGPoint(x: 2, y: 2)), by: offset)
            == .arrow(from: CGPoint(x: 10, y: -5), to: CGPoint(x: 11, y: -4), curve: CGPoint(x: 12, y: -3)))
        #expect(Geometry.moved(.highlight(rect, spotlight: true), by: offset) == .highlight(rect.offsetBy(dx: 10, dy: -5), spotlight: true))
        #expect(Geometry.moved(.text(at: .zero, text: "x", pill: false, leader: CGPoint(x: 1, y: 1)), by: offset)
            == .text(at: CGPoint(x: 10, y: -5), text: "x", pill: false, leader: CGPoint(x: 11, y: -4)))
        #expect(Geometry.moved(.unknown(.null, reason: "x"), by: offset) == .unknown(.null, reason: "x"))
    }

    @Test func cropStaysInsideTheImageAndCanLockItsAspect() {
        let image = PixelSize(width: 1600, height: 1000)
        #expect(Geometry.clampedCrop(CGRect(x: -50, y: 900, width: 400, height: 300), to: image) == CGRect(x: 0, y: 900, width: 350, height: 100))
        #expect(Geometry.clampedCrop(CGRect(x: 2000, y: 0, width: 10, height: 10), to: image) == nil)
        #expect(Geometry.fitted(CGRect(x: 0, y: 0, width: 400, height: 100), aspect: 2) == CGRect(x: 100, y: 0, width: 200, height: 100))
        #expect(Geometry.fitted(CGRect(x: 0, y: 0, width: 100, height: 400), aspect: 2) == CGRect(x: 0, y: 175, width: 100, height: 50))
    }
}
