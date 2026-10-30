import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct BoundsTests {
    private let style = Styles.builtIn.style(for: 1)

    @Test func presetsFallBackToTheFirst() {
        #expect(Styles.builtIn.style(for: 2).strokeWidth > style.strokeWidth)
        #expect(Styles.builtIn.style(for: 42) == style)
    }

    @Test func outlinedShapesGrowByHalfTheStroke() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 80)
        let half = style.strokeWidth / 2
        for shape in [Shape.rectangle(rect, fill: false), .ellipse(rect, fill: true)] {
            #expect(Geometry.bounds(of: shape, style: style) == rect.insetBy(dx: -half, dy: -half))
        }
        for shape in [Shape.highlight(rect, spotlight: true), .blur(rect, pixelate: false)] {
            #expect(Geometry.bounds(of: shape, style: style) == rect)
        }
    }

    @Test func counterIsItsCircle() {
        let r = style.counterRadius
        #expect(Geometry.bounds(of: .counter(at: CGPoint(x: 50, y: 60)), style: style) == CGRect(x: 50 - r, y: 60 - r, width: 2 * r, height: 2 * r))
    }

    @Test func arrowCoversItsEndsHeadAndCurve() {
        let from = CGPoint(x: 600, y: 300)
        let to = CGPoint(x: 412, y: 240)
        let bounds = Geometry.bounds(of: .arrow(from: from, to: to, curve: nil), style: style)
        #expect(bounds.insetBy(dx: style.strokeWidth, dy: style.strokeWidth).contains(from))
        #expect(bounds.insetBy(dx: style.strokeWidth, dy: style.strokeWidth).contains(to))
        let curved = Geometry.bounds(of: .arrow(from: from, to: to, curve: CGPoint(x: 500, y: 100)), style: style)
        #expect(curved.minY < bounds.minY)
    }

    @Test func textIsMeasuredWithItsFont() {
        let at = CGPoint(x: 10, y: 20)
        let small = Geometry.bounds(of: .text(at: at, text: "Chọn VM cần dừng", pill: false, leader: nil), style: style)
        #expect(small.origin == at)
        #expect(small.width > 100)
        #expect(small.height > style.fontSize * 0.9)
        let large = Geometry.bounds(of: .text(at: at, text: "Chọn VM cần dừng", pill: false, leader: nil), style: Styles.builtIn.style(for: 2))
        #expect(large.width > small.width)
        let twoLines = Geometry.bounds(of: .text(at: at, text: "Chọn VM\ncần dừng", pill: false, leader: nil), style: style)
        #expect(twoLines.height > small.height * 1.8)
        #expect(twoLines.width < small.width)
        let pill = Geometry.bounds(of: .text(at: at, text: "Chọn VM cần dừng", pill: true, leader: nil), style: style)
        #expect(pill.contains(small))
        #expect(pill.width > small.width)
        let leader = Geometry.bounds(of: .text(at: at, text: "x", pill: false, leader: CGPoint(x: 500, y: 400)), style: style)
        #expect(leader.maxX >= 500)
        #expect(leader.maxY >= 400)
    }

    @Test func unknownItemsHaveNoBounds() {
        #expect(Geometry.bounds(of: .unknown(.null, reason: "x"), style: style).isNull)
    }
}
