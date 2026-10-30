import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct SnapperTests {
    private let image = PixelSize(width: 1600, height: 1000)

    @Test func pointsSnapToImageEdgesAndCentre() {
        let snapper = Snapper(imageSize: image, threshold: 6)
        let edge = snapper.snap(CGPoint(x: 3, y: 500))
        #expect(edge.point == CGPoint(x: 0, y: 500))
        #expect(edge.guides == [Snapper.Guide(axis: .x, position: 0), Snapper.Guide(axis: .y, position: 500)])
        let corner = snapper.snap(CGPoint(x: 1597, y: 996))
        #expect(corner.point == CGPoint(x: 1600, y: 1000))
        let free = snapper.snap(CGPoint(x: 300, y: 300))
        #expect(free.point == CGPoint(x: 300, y: 300))
        #expect(free.guides.isEmpty)
    }

    @Test func pointsSnapToOtherObjectsEdgesAndCentres() {
        let snapper = Snapper(imageSize: image, targets: [CGRect(x: 200, y: 200, width: 100, height: 60)], threshold: 6)
        let result = snapper.snap(CGPoint(x: 252, y: 404))
        #expect(result.point == CGPoint(x: 250, y: 404))
        #expect(result.guides == [Snapper.Guide(axis: .x, position: 250)])
    }

    @Test func aMovedRectSnapsByItsClosestEdgeOrCentre() {
        let snapper = Snapper(imageSize: image, targets: [CGRect(x: 200, y: 200, width: 100, height: 60)], threshold: 6)
        let moved = snapper.snap(CGRect(x: 304, y: 403, width: 50, height: 50))
        #expect(moved.rect == CGRect(x: 300, y: 403, width: 50, height: 50))
        #expect(moved.guides == [Snapper.Guide(axis: .x, position: 300)])
        let centred = snapper.snap(CGRect(x: 226, y: 500, width: 50, height: 50))
        #expect(centred.rect.midX == 250)
    }

    @Test func theGridCatchesWhatNothingElseDoes() {
        let snapper = Snapper(imageSize: image, grid: 8, threshold: 6)
        let result = snapper.snap(CGPoint(x: 13, y: 21))
        #expect(result.point == CGPoint(x: 16, y: 24))
        #expect(result.guides.isEmpty)
        let edge = snapper.snap(CGPoint(x: 4, y: 21))
        #expect(edge.point == CGPoint(x: 0, y: 24))
        #expect(edge.guides == [Snapper.Guide(axis: .x, position: 0)])
        #expect(snapper.snap(CGRect(x: 13, y: 21, width: 30, height: 30)).rect.origin == CGPoint(x: 16, y: 24))
    }

    @Test func targetsLeaveOutTheSelectionAndUnknownItems() {
        let a = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), fill: true))
        let b = Annotation(shape: .highlight(CGRect(x: 50, y: 50, width: 10, height: 10), spotlight: false))
        let unknown = Annotation(shape: .unknown(.null, reason: "x"))
        let targets = Snapper.targets(in: [a, b, unknown], excluding: [a.id], styles: .builtIn)
        #expect(targets == [CGRect(x: 50, y: 50, width: 10, height: 10)])
    }
}
