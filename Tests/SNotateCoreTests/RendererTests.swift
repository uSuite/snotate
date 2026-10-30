import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct RendererTests {
    @Test func withoutAnnotationsTheRenderIsTheCapture() {
        let image = Renderer.render(Scene(image: Golden.capture, items: []))
        #expect(image.width == 1600)
        #expect(image.height == 1000)
        #expect(Golden.pixels(image) == Golden.pixels(Golden.capture))
    }

    @Test func theRenderKeepsTheTopRowOnTop() {
        let image = Renderer.render(Scene(image: Golden.capture, items: []))
        // The fixture's title bar is dark and its page light.
        #expect(Golden.pixel(image, 800, 10)[0] < 60)
        #expect(Golden.pixel(image, 800, 990)[0] > 200)
    }

    @Test func aCropCutsTheRenderToThatRectangle() {
        let crop = CGRect(x: 0, y: 64, width: 1600, height: 936)
        let image = Renderer.render(Scene(image: Golden.capture, items: []), crop: crop)
        #expect(image.width == 1600)
        #expect(image.height == 936)
        #expect(Golden.pixel(image, 800, 0) == Golden.pixel(Golden.capture, 800, 64))
    }

    @Test func theSamePictureGivesTheSameBytes() {
        let scene = Scene(image: Golden.capture, items: [])
        #expect(Renderer.pngData(Renderer.render(scene)) == Renderer.pngData(Renderer.render(scene)))
    }
}

struct RendererLayerTests {
    @Test func aCachedBaseUnderTheAnnotationsIsTheFullRender() {
        let scene = Scene(image: Golden.capture, items: [
            Annotation(shape: .blur(CGRect(x: 300, y: 12, width: 150, height: 40), pixelate: false)),
            Annotation(shape: .arrow(from: CGPoint(x: 1000, y: 600), to: CGPoint(x: 762, y: 720), curve: nil), preset: 2),
            Annotation(shape: .counter(at: CGPoint(x: 392, y: 726))),
        ])
        let base = Renderer.base(scene)
        let context = Renderer.bitmap(width: base.width, height: base.height)
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)
        Renderer.drawImage(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height), context: context)
        Renderer.drawAnnotations(scene, in: context)
        #expect(Golden.pixels(context.makeImage()!) == Golden.pixels(Renderer.render(scene)))
    }
}

struct RedactionStrengthTests {
    @Test func consoleFieldsKeepThePresetRadiusLargeRegionsGrow() {
        let field = CGSize(width: 150, height: 40)
        #expect(Renderer.redactionStrength(field, radius: 12, pixelate: true) == 12)
        #expect(Renderer.redactionStrength(field, radius: 12, pixelate: false) == 12)
        let label = CGSize(width: 540, height: 130)
        #expect(Renderer.redactionStrength(label, radius: 12, pixelate: true) == 32.5)
        #expect(Renderer.redactionStrength(label, radius: 12, pixelate: false) == 26)
        #expect(Renderer.redactionStrength(CGSize(width: 3, height: 3), radius: 0, pixelate: true) == 2)
    }
}
