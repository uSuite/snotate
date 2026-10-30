import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

/// One golden per tool on the second sample capture. Positions follow the
/// fixture's console: card from (320, 140) to (1540, 880), buttons at
/// y 726 to 790, sidebar rows from y 98.
struct GoldenShapeTests {
    private func render(_ shapes: [(Shape, Int)]) -> CGImage {
        Renderer.render(Scene(
            image: Golden.capture,
            items: shapes.map { Annotation(shape: $0.0, preset: $0.1) }
        ))
    }

    @Test func arrow() throws {
        try Golden.check(render([
            (.arrow(from: CGPoint(x: 1000, y: 600), to: CGPoint(x: 762, y: 720), curve: nil), 1),
            (.arrow(from: CGPoint(x: 330, y: 620), to: CGPoint(x: 140, y: 140), curve: CGPoint(x: 420, y: 300)), 2),
        ]), "arrow")
    }

    @Test func rectangle() throws {
        try Golden.check(render([
            (.rectangle(CGRect(x: 380, y: 714, width: 244, height: 88), fill: false), 2),
            (.rectangle(CGRect(x: 900, y: 714, width: 244, height: 88), fill: true), 1),
        ]), "rectangle")
    }

    @Test func ellipse() throws {
        try Golden.check(render([
            (.ellipse(CGRect(x: 360, y: 170, width: 600, height: 170), fill: false), 2),
            (.ellipse(CGRect(x: 1300, y: 300, width: 150, height: 100), fill: true), 3),
        ]), "ellipse")
    }

    @Test func highlight() throws {
        try Golden.check(render([
            (.highlight(CGRect(x: 384, y: 386, width: 302, height: 52), spotlight: false), 1),
            (.highlight(CGRect(x: 1140, y: 714, width: 120, height: 88), spotlight: false), 2),
        ]), "highlight")
    }

    @Test func spotlight() throws {
        try Golden.check(render([
            (.highlight(CGRect(x: 16, y: 90, width: 228, height: 48), spotlight: true), 1),
            (.rectangle(CGRect(x: 16, y: 90, width: 228, height: 48), fill: false), 2),
        ]), "spotlight")
    }
}

struct GoldenTextTests {
    @Test func counter() throws {
        let items = [
            Annotation(shape: .counter(at: CGPoint(x: 392, y: 726)), preset: 1),
            Annotation(shape: .counter(at: CGPoint(x: 652, y: 726)), preset: 2),
            Annotation(shape: .counter(at: CGPoint(x: 912, y: 726)), preset: 3),
            Annotation(shape: .counter(at: CGPoint(x: 1200, y: 600)), preset: 1),
            Annotation(shape: .counter(at: CGPoint(x: 1300, y: 600)), preset: 1),
        ]
        let numbers = [items[0].id: 1, items[1].id: 2, items[2].id: 3, items[3].id: 12]
        try Golden.check(Renderer.render(Scene(image: Golden.capture, items: items, numbers: numbers)), "counter")
    }

    @Test func text() throws {
        try Golden.check(Renderer.render(Scene(image: Golden.capture, items: [
            Annotation(shape: .text(at: CGPoint(x: 340, y: 900), text: "Chọn VM cần dừng rồi bấm Dừng", pill: false, leader: nil), preset: 2),
            Annotation(shape: .text(at: CGPoint(x: 1000, y: 480), text: "Two lines\nof notes", pill: false, leader: nil), preset: 3),
            Annotation(shape: .text(at: CGPoint(x: 280, y: 20), text: "Over the title bar", pill: false, leader: nil), preset: 1),
        ])), "text")
    }

    @Test func textPill() throws {
        try Golden.check(Renderer.render(Scene(image: Golden.capture, items: [
            Annotation(shape: .text(at: CGPoint(x: 1000, y: 560), text: "Press Migrate", pill: true, leader: CGPoint(x: 762, y: 726)), preset: 1),
            Annotation(shape: .text(at: CGPoint(x: 1240, y: 220), text: "Bước 2\nchọn máy chủ", pill: true, leader: nil), preset: 2),
            Annotation(shape: .text(at: CGPoint(x: 600, y: 920), text: "pill", pill: true, leader: CGPoint(x: 130, y: 170)), preset: 3),
        ])), "text-pill")
    }
}

struct GoldenRedactionTests {
    private let items = [
        Annotation(shape: .rectangle(CGRect(x: 296, y: 8, width: 158, height: 48), fill: false), preset: 2),
        Annotation(shape: .blur(CGRect(x: 300, y: 12, width: 150, height: 40), pixelate: false), preset: 1),
        Annotation(shape: .counter(at: CGPoint(x: 454, y: 12)), preset: 1),
        Annotation(shape: .blur(CGRect(x: 380, y: 230, width: 540, height: 130), pixelate: true), preset: 1),
    ]

    @Test func blur() throws {
        let numbers = [items[2].id: 1]
        let image = Renderer.render(Scene(image: Golden.capture, items: items, numbers: numbers))
        try Golden.check(image, "blur")
        // The region changed; the rectangle drawn before the blur in item
        // order and the counter on it stay crisp.
        #expect(Golden.pixel(image, 330, 32) != Golden.pixel(Golden.capture, 330, 32))
        #expect(Golden.pixel(image, 296, 30) == [0xC6, 0x28, 0x28, 0xFF])
        #expect(Golden.pixel(image, 448, 12) == [0x00, 0x57, 0x9C, 0xFF])
        #expect(Golden.pixel(image, 800, 600) == Golden.pixel(Golden.capture, 800, 600))
    }

    @Test func blurIsDeterministic() {
        let scene = Scene(image: Golden.capture, items: items)
        #expect(Renderer.pngData(Renderer.render(scene)) == Renderer.pngData(Renderer.render(scene)))
    }
}

struct GoldenStepTests {
    private let items = [
        Annotation(shape: .counter(at: CGPoint(x: 392, y: 726)), preset: 1),
        Annotation(shape: .arrow(from: CGPoint(x: 1000, y: 600), to: CGPoint(x: 762, y: 720), curve: nil), preset: 2),
        Annotation(shape: .text(at: CGPoint(x: 1010, y: 560), text: "Bấm Migrate", pill: true, leader: nil), preset: 1),
        Annotation(shape: .rectangle(CGRect(x: 1400, y: 100, width: 300, height: 120), fill: false), preset: 3),
    ]

    private func numbers() -> [UUID: Int] {
        [items[0].id: 1]
    }

    private func blank(_ width: Int, _ height: Int) -> CGImage {
        let context = Renderer.bitmap(width: width, height: height)
        context.setFillColor(RGBA.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func crop() throws {
        let crop = CGRect(x: 320, y: 140, width: 1220, height: 740)
        let image = Renderer.render(Scene(image: Golden.capture, items: items, numbers: numbers()), crop: crop)
        #expect(image.width == 1220)
        #expect(image.height == 740)
        try Golden.check(image, "crop")
    }

    @Test func scaledStepLooksLikeItsOriginal() throws {
        let two = Renderer.loadImage(at: Fixtures.url("poc-sample-vm-scale/poc-sample-vm-scale-01.png"))!
        let large = Renderer.render(Scene(
            image: two,
            items: items,
            numbers: numbers(),
            transform: StepTransform(scale: .scaled(2))
        ))
        #expect(large.width == 3200)
        try Golden.check(large, "scaled-2x")
        // The fixture's 1x and 2x captures differ in panel and title, so the
        // annotation layers are compared on blank pages: scaled down, the 2x
        // layer is the 1x layer up to antialiasing.
        let layerOne = Renderer.render(Scene(image: blank(1600, 1000), items: items, numbers: numbers()))
        let layerTwo = Renderer.render(Scene(
            image: blank(3200, 2000),
            items: items,
            numbers: numbers(),
            transform: StepTransform(scale: .scaled(2))
        ))
        let context = Renderer.bitmap(width: 1600, height: 1000)
        context.interpolationQuality = .high
        context.draw(layerTwo, in: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        let a = Golden.pixels(context.makeImage()!)
        let b = Golden.pixels(layerOne)
        // Measured only where the 1x layer draws, so the white page does not
        // dilute the difference.
        var drawn = 0
        var total = 0
        for pixel in stride(from: 0, to: b.count, by: 4) where (0..<3).contains(where: { b[pixel + $0] < 250 }) {
            drawn += 1
            total += (0..<3).map { abs(Int(a[pixel + $0]) - Int(b[pixel + $0])) }.reduce(0, +)
        }
        #expect(drawn > 10_000)
        #expect(Double(total) / Double(drawn * 3) < 12)
    }
}

struct GoldenSpotlightTests {
    @Test func spotlightsShareOneDimmingWithAHoleEach() throws {
        let image = Renderer.render(Scene(image: Golden.capture, items: [
            Annotation(shape: .highlight(CGRect(x: 380, y: 714, width: 244, height: 88), spotlight: true)),
            Annotation(shape: .highlight(CGRect(x: 600, y: 700, width: 300, height: 120), spotlight: true)),
            Annotation(shape: .highlight(CGRect(x: 1100, y: 300, width: 200, height: 100), spotlight: true)),
        ]))
        try Golden.check(image, "spotlight-two")
        // Inside every hole, the overlap included, the capture is untouched.
        for (x, y) in [(400, 750), (610, 750), (850, 790), (1200, 350)] {
            #expect(Golden.pixel(image, x, y) == Golden.pixel(Golden.capture, x, y), "(\(x), \(y))")
        }
        // Outside, the capture is dimmed once, not once per spotlight.
        let outside = Golden.pixel(image, 800, 950)
        let original = Golden.pixel(Golden.capture, 800, 950)
        let expected = (0..<3).map { Int((Double(original[$0]) * 0.55).rounded()) }
        #expect((0..<3).allSatisfy { abs(Int(outside[$0]) - expected[$0]) <= 2 })
    }
}
