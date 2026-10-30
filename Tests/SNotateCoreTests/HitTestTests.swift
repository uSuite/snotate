import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct HitTestTests {
    private let style = Styles.builtIn.style(for: 1)

    private func hits(_ shape: Shape, _ x: CGFloat, _ y: CGFloat, tolerance: CGFloat = 2) -> Bool {
        Geometry.hits(shape, CGPoint(x: x, y: y), style: style, tolerance: tolerance)
    }

    @Test func arrowsAreHitNearTheLine() {
        let arrow = Shape.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), curve: nil)
        #expect(hits(arrow, 50, 0))
        #expect(hits(arrow, 50, 3.5))
        #expect(!hits(arrow, 50, 10))
        #expect(!hits(arrow, 120, 0))
        let curved = Shape.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), curve: CGPoint(x: 50, y: 100))
        // The quadratic's midpoint is halfway to the control point.
        #expect(hits(curved, 50, 50))
        #expect(!hits(curved, 50, 0))
    }

    @Test func outlinesAreHitOnTheEdgeFillsInside() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(hits(.rectangle(rect, fill: false), 100, 150))
        #expect(hits(.rectangle(rect, fill: false), 200, 202))
        #expect(!hits(.rectangle(rect, fill: false), 200, 150))
        #expect(hits(.rectangle(rect, fill: true), 200, 150))
        #expect(!hits(.rectangle(rect, fill: true), 90, 150))
        #expect(hits(.ellipse(rect, fill: false), 100, 150))
        #expect(hits(.ellipse(rect, fill: false), 200, 101))
        #expect(!hits(.ellipse(rect, fill: false), 200, 150))
        #expect(!hits(.ellipse(rect, fill: false), 105, 105))
        #expect(hits(.ellipse(rect, fill: true), 200, 150))
        #expect(!hits(.ellipse(rect, fill: true), 105, 105))
    }

    @Test func areasCountersAndTextAreHitInside() {
        let rect = CGRect(x: 0, y: 0, width: 50, height: 50)
        #expect(hits(.highlight(rect, spotlight: false), 25, 25))
        #expect(hits(.blur(rect, pixelate: true), 51, 25))
        #expect(!hits(.blur(rect, pixelate: true), 60, 25))
        #expect(hits(.counter(at: CGPoint(x: 100, y: 100)), 100 + style.counterRadius, 100))
        #expect(!hits(.counter(at: CGPoint(x: 100, y: 100)), 100 + style.counterRadius + 5, 100))
        let text = Shape.text(at: CGPoint(x: 10, y: 10), text: "Start", pill: false, leader: nil)
        #expect(hits(text, 20, 20))
        #expect(!hits(text, 5, 5, tolerance: 1))
        #expect(!hits(.unknown(.null, reason: "x"), 0, 0))
    }

    @Test func theTopmostAnnotationWins() {
        let below = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), fill: true))
        let above = Annotation(shape: .counter(at: CGPoint(x: 50, y: 50)))
        let items = [below, above]
        #expect(Geometry.topmost(at: CGPoint(x: 50, y: 50), in: items, styles: .builtIn, tolerance: 2) == above.id)
        #expect(Geometry.topmost(at: CGPoint(x: 5, y: 5), in: items, styles: .builtIn, tolerance: 2) == below.id)
        #expect(Geometry.topmost(at: CGPoint(x: 500, y: 500), in: items, styles: .builtIn, tolerance: 2) == nil)
    }

    @Test func aMarqueeSelectsWhatItTouches() {
        let left = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), fill: false))
        let right = Annotation(shape: .counter(at: CGPoint(x: 400, y: 50)))
        let unknown = Annotation(shape: .unknown(.null, reason: "x"))
        let items = [left, right, unknown]
        #expect(Geometry.marquee(CGRect(x: 90, y: 40, width: 50, height: 20), in: items, styles: .builtIn) == [left.id])
        #expect(Geometry.marquee(CGRect(x: 50, y: 0, width: 400, height: 100), in: items, styles: .builtIn) == [left.id, right.id])
        #expect(Geometry.marquee(CGRect(x: 200, y: 200, width: 10, height: 10), in: items, styles: .builtIn).isEmpty)
    }
}
