import CoreGraphics
import Testing
@testable import SNotateCore

struct ViewportTests {
    /// A 1600 x 1000 capture in a 1100 x 720 view on a Retina screen, where
    /// fit is capped at actual size.
    private let frame = Viewport.Frame(imageSize: CGSize(width: 1600, height: 1000), viewSize: CGSize(width: 1100, height: 720))
    /// The same capture re-shot at 2x.
    private let double = Viewport.Frame(imageSize: CGSize(width: 3200, height: 2000), factor: 2, viewSize: CGSize(width: 1100, height: 720))

    @Test func fitIsNeverAboveActualSizeAndCentresTheImage() {
        let viewport = Viewport()
        #expect(viewport.scale(in: frame) == 1)
        #expect(viewport.transform(in: frame) == ViewTransform(scale: 0.5, offset: CGPoint(x: 150, y: 110)))
        let small = Viewport.Frame(imageSize: CGSize(width: 1600, height: 1000), viewSize: CGSize(width: 400, height: 400))
        #expect(viewport.scale(in: small) == 0.5)
        #expect(viewport.transform(in: small) == ViewTransform(scale: 0.25, offset: CGPoint(x: 0, y: 75)))
        #expect(viewport.overflows(in: small) == (false, false))
    }

    @Test func zoomKeepsTheAnchoredPointStill() {
        var viewport = Viewport()
        let anchor = CGPoint(x: 550, y: 400)
        let before = viewport.transform(in: frame).toImage(anchor)
        viewport.zoom(by: 2, at: anchor, in: frame)
        #expect(viewport.zoom == .scale(2))
        let after = viewport.transform(in: frame)
        #expect(after.scale == 1)
        #expect(after.toView(before) == anchor)
        #expect(viewport.ratio(in: frame) == 2)
    }

    @Test func zoomStaysInItsRange() {
        var viewport = Viewport()
        viewport.zoom(by: 1000, in: frame)
        #expect(viewport.zoom == .scale(16))
        viewport.zoom(by: 0.0001, in: frame)
        #expect(viewport.zoom == .scale(0.1))
    }

    @Test func theImageKeepsCoveringTheViewWhenPannedOrZoomedAtAnEdge() {
        var viewport = Viewport()
        viewport.zoom(by: 2, at: .zero, in: frame)
        #expect(viewport.transform(in: frame).offset == .zero)
        viewport.pan(by: CGVector(dx: 500, dy: 500), in: frame)
        #expect(viewport.transform(in: frame).offset == .zero)
        viewport.pan(by: CGVector(dx: -300, dy: -100), in: frame)
        #expect(viewport.transform(in: frame).offset == CGPoint(x: -300, y: -100))
        viewport.pan(by: CGVector(dx: -10_000, dy: -10_000), in: frame)
        #expect(viewport.transform(in: frame).offset == CGPoint(x: 1100 - 1600, y: 720 - 1000))
        #expect(viewport.overflows(in: frame) == (true, true))
    }

    @Test func panDoesNothingAtFit() {
        var viewport = Viewport()
        viewport.pan(by: CGVector(dx: 50, dy: 0), in: frame)
        #expect(viewport == Viewport())
    }

    @Test func anAxisThatFitsStaysCentred() {
        var viewport = Viewport()
        // 1120 x 700 points: wider than the view, not taller.
        viewport.zoom(by: 1.4, in: frame)
        #expect(viewport.overflows(in: frame) == (true, false))
        viewport.pan(by: CGVector(dx: 0, dy: 400), in: frame)
        #expect(viewport.transform(in: frame).offset.y == 10)
    }

    @Test func actualSizeIsOneDevicePixelPerImagePixel() {
        var viewport = Viewport()
        viewport.zoom(by: 3, in: frame)
        viewport.actual(in: frame)
        #expect(viewport.zoom == .scale(1))
        viewport.actual(in: double)
        #expect(viewport.zoom == .scale(2))
        #expect(viewport.transform(in: double).scale == 0.5)
        viewport.fit()
        #expect(viewport == Viewport())
    }

    @Test func aDoubleStepShowsTheSameRegion() {
        var viewport = Viewport()
        viewport.zoom(by: 2, at: CGPoint(x: 400, y: 300), in: frame)
        let region = viewport.transform(in: frame).toImage(CGRect(x: 0, y: 0, width: 1100, height: 720))
        let doubled = viewport.transform(in: double).toImage(CGRect(x: 0, y: 0, width: 1100, height: 720))
        #expect(doubled == StepTransform(scale: .scaled(2)).toImage(region))
        #expect(viewport.ratio(in: double) == 1)
        // Twice the pixels fit wider before reaching actual size.
        #expect(Viewport().transform(in: double) == ViewTransform(scale: 0.34375, offset: CGPoint(x: 0, y: 16.5)))
    }

    @Test func showingARectFillsTheViewWithIt() {
        var viewport = Viewport()
        viewport.show(CGRect(x: 200, y: 100, width: 550, height: 180), in: frame)
        // Width limits: 1100 points over 550 pixels is 2 points, 4 device pixels.
        #expect(viewport.zoom == .scale(4))
        let transform = viewport.transform(in: frame)
        #expect(transform.toView(CGPoint(x: 475, y: 190)) == CGPoint(x: 550, y: 360))
        viewport.show(CGRect(x: 0, y: 0, width: 0, height: 10), in: frame)
        #expect(viewport.zoom == .scale(4))
        viewport.show(CGRect(x: 10, y: 10, width: 2, height: 2), in: frame)
        #expect(viewport.zoom == .scale(16))
    }
}
