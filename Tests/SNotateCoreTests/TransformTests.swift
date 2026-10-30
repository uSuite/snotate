import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct GeometryCodingTests {
    @Test func pointsAndRectsRoundTrip() throws {
        #expect(try Sidecar.point(.array([.number(412), .number(230.5)]), "at") == CGPoint(x: 412, y: 230.5))
        #expect(Sidecar.json(CGPoint(x: 1, y: 2)) == .array([.number(1), .number(2)]))
        let rect = CGRect(x: 0, y: 88, width: 1920, height: 992)
        #expect(try Sidecar.rect(Sidecar.json(rect), "rect") == rect)
    }

    @Test func rectsAreNormalisedOnRead() throws {
        let flipped = JSONValue.array([.number(100), .number(50), .number(-40), .number(-20)])
        #expect(try Sidecar.rect(flipped, "rect") == CGRect(x: 60, y: 30, width: 40, height: 20))
    }

    @Test func badShapesNameTheKey() {
        #expect(throws: SidecarError.wrongType(key: "at", expected: "[x, y]")) {
            try Sidecar.point(.array([.number(1)]), "at")
        }
        #expect(throws: SidecarError.wrongType(key: "rect", expected: "[x, y, width, height]")) {
            try Sidecar.rect(.array([.number(1), .number(2), .string("3"), .number(4)]), "rect")
        }
    }
}

struct TransformTests {
    @Test func storedCoordinatesFollowTheScaleRule() {
        let double = StepTransform(scale: .scaled(2))
        #expect(double.toImage(CGPoint(x: 10, y: 20)) == CGPoint(x: 20, y: 40))
        #expect(double.toStored(CGPoint(x: 20, y: 40)) == CGPoint(x: 10, y: 20))
        #expect(double.toImage(CGRect(x: 1, y: 2, width: 3, height: 4)) == CGRect(x: 2, y: 4, width: 6, height: 8))
        let half = StepTransform(scale: .scaled(0.5))
        #expect(half.toImage(CGPoint(x: 1518, y: 892)) == CGPoint(x: 759, y: 446))
        #expect(half.toStored(CGRect(x: 2, y: 4, width: 6, height: 8)) == CGRect(x: 4, y: 8, width: 12, height: 16))
    }

    @Test func matchedFlaggedAndUnknownStepsAreUnscaled() {
        let odd = StepScale.mismatch(
            recorded: PixelSize(width: 1600, height: 1000),
            actual: PixelSize(width: 1592, height: 982)
        )
        for scale in [StepScale.match, odd, nil] {
            #expect(StepTransform(scale: scale).factor == 1)
        }
    }

    @Test func viewTransformMapsBothWays() {
        let view = ViewTransform(scale: 0.5, offset: CGPoint(x: 10, y: 20))
        #expect(view.toView(CGPoint(x: 100, y: 200)) == CGPoint(x: 60, y: 120))
        #expect(view.toImage(CGPoint(x: 60, y: 120)) == CGPoint(x: 100, y: 200))
        #expect(view.toView(CGRect(x: 0, y: 0, width: 100, height: 50)) == CGRect(x: 10, y: 20, width: 50, height: 25))
        #expect(view.toImage(CGRect(x: 10, y: 20, width: 50, height: 25)) == CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(view.toImage(length: 6) == 12)
    }
}
