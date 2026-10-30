import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct ThumbnailTests {
    private func scene(_ document: CaseDocument, _ n: Int) throws -> (Scene, CGRect?) {
        let file = AnnotatedCase.file(n)
        let step = try #require(document.steps.first { $0.file == file })
        let entry = try #require(document.sidecar.steps.first { $0.file == file })
        let image = try #require(Renderer.loadImage(at: step.url))
        let scene = Scene(
            image: image,
            items: entry.items,
            numbers: document.counterNumbers,
            transform: StepTransform(scale: step.scale),
            styles: .builtIn
        )
        return (scene, entry.crop)
    }

    @Test func aThumbnailIsTheExportScaledDown() throws {
        let annotated = try AnnotatedCase()
        let document = try annotated.document()
        for n in [0, 2, 4] {
            let (scene, crop) = try scene(document, n)
            let export = Renderer.render(scene, crop: crop)
            let thumbnail = Renderer.thumbnail(scene, crop: crop, width: 400)
            #expect(thumbnail.width == 400)
            #expect(abs(CGFloat(thumbnail.height) - CGFloat(export.height) * 400 / CGFloat(export.width)) <= 1)
            // The export resampled the plain way is close to the thumbnail.
            let context = Renderer.bitmap(width: thumbnail.width, height: thumbnail.height)
            context.interpolationQuality = .high
            context.draw(export, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
            let reference = try #require(context.makeImage())
            let a = Golden.pixels(thumbnail)
            let b = Golden.pixels(reference)
            let differing = stride(from: 0, to: a.count, by: 4).filter { i in
                (0..<3).contains { abs(Int(a[i + $0]) - Int(b[i + $0])) > 48 }
            }.count
            #expect(Double(differing) / Double(a.count / 4) < 0.03)
        }
    }

    @Test func thirtyThumbnailsRenderQuickly() throws {
        let annotated = try AnnotatedCase()
        let document = try annotated.document()
        let scenes = try (0..<5).map { try scene(document, $0) }
        let start = Date()
        for index in 0..<30 {
            let (scene, crop) = scenes[index % scenes.count]
            _ = Renderer.thumbnail(scene, crop: crop, width: 320)
        }
        // Generous for debug builds and busy machines; the app renders them
        // off the main thread after the grid is on screen.
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
