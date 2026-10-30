import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SNotateCore

struct ExportOptionsTests {
    private func notated(_ annotated: AnnotatedCase, _ name: String) -> URL {
        annotated.folder.appendingPathComponent("notated/\(name)")
    }

    private func options(_ change: (inout ExportOptions) -> Void) -> ExportOptions {
        var options = ExportOptions()
        change(&options)
        return options
    }

    @Test func theConfigCarriesTheOptionsAndRefusesBadValues() {
        let (config, issues) = SNotateConfig.parse("""
            export_scale 2
            export_format JPEG
            jpeg_quality 75
            export_counters off
            export_captions yes
            export_scale 3
            export_format webp
            jpeg_quality 0
            """)
        let options = ExportOptions(config: config)
        #expect(options.scale == 2)
        #expect(options.format == .jpeg)
        #expect(options.jpegQuality == 75)
        #expect(!options.counters)
        #expect(options.captions)
        #expect(issues.map(\.description) == [
            "line 6: export_scale: '3' is not 0.5, 1 or 2",
            "line 7: export_format: 'webp' is not png or jpeg",
            "line 8: jpeg_quality: '0' is not a whole number from 1 to 100",
        ])
        #expect(ExportOptions(config: SNotateConfig()) == ExportOptions())
    }

    @Test func jpegIsStableSoASecondExportWritesNothing() throws {
        let annotated = try AnnotatedCase()
        let document = try annotated.document()
        let jpeg = options { $0.format = .jpeg; $0.labels = .off }
        let first = try Exporter.exportCase(document, options: jpeg)
        #expect(first.written.allSatisfy { $0.hasSuffix(".jpg") })
        let second = try Exporter.exportCase(document, options: jpeg)
        #expect(second.written.isEmpty)
        #expect(second.unchanged.count == 5)
        let image = try #require(Renderer.loadImage(at: notated(annotated, AnnotatedCase.file(0).replacingOccurrences(of: ".png", with: ".jpg"))))
        #expect(image.width == 1600)
    }

    @Test func switchingFormatRemovesTheOtherFormatsFiles() throws {
        let annotated = try AnnotatedCase()
        let document = try annotated.document()
        _ = try Exporter.exportCase(document, options: options { $0.labels = .off })
        let report = try Exporter.exportCase(document, options: options { $0.format = .jpeg; $0.labels = .off })
        #expect(report.removed.count == 5)
        #expect(report.removed.allSatisfy { $0.hasSuffix(".png") })
        let names = try FileManager.default.contentsOfDirectory(atPath: annotated.folder.appendingPathComponent("notated").path)
        #expect(names.sorted() == (0...4).map { String(format: "\(AnnotatedCase.name)-%02d.jpg", $0) })
    }

    @Test func scaleMultipliesTheNativeSize() throws {
        let annotated = try AnnotatedCase()
        let document = try annotated.document()
        for (scale, width) in [(CGFloat(0.5), 800), (2, 3200)] {
            let data = try Exporter.exportedData(for: AnnotatedCase.file(0), of: document, options: options { $0.scale = scale })
            let image = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            #expect(image.width == width)
        }
        // Step 02 is cropped to 1220 x 760.
        let cropped = try Exporter.exportedData(for: AnnotatedCase.file(2), of: document, options: options { $0.scale = 0.5 })
        #expect(CGImageSourceCreateWithData(cropped as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width == 610)
    }

    @Test func countersCanBeLeftOut() throws {
        let annotated = try AnnotatedCase()
        let data = try Exporter.exportedData(for: AnnotatedCase.file(2), of: try annotated.document(), options: options { $0.counters = false })
        try Golden.check(try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }), "export-no-counters")
    }

    @Test func aCaptionIsBurnedUnderTheImageWithItsBold() throws {
        let annotated = try AnnotatedCase()
        let document = try annotated.document()
        #expect(document.caption(for: AnnotatedCase.file(1)) == "Open **Actions** > **Migrate** on the VM")
        let data = try Exporter.exportedData(for: AnnotatedCase.file(1), of: document, options: options { $0.captions = true })
        let image = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == 1600)
        #expect(image.height > 1000)
        #expect(Golden.pixel(image, 4, image.height - 4) == [255, 255, 255, 255])
        try Golden.check(image, "export-caption")
        let bare = try Exporter.exportedData(for: AnnotatedCase.file(3), of: try placeholder(annotated), options: options { $0.captions = true })
        #expect(CGImageSourceCreateWithData(bare as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.height == 1000)
    }

    /// The case with step 03's caption back to the evidence script's
    /// placeholder, which is no caption.
    private func placeholder(_ annotated: AnnotatedCase) throws -> CaseDocument {
        var document = try annotated.document()
        let data = try #require(try document.memo?.settingCaption(Memo.placeholder, for: AnnotatedCase.file(3)))
        document.memo = try Memo(data: data)
        return document
    }

    @Test func unpairedAsterisksStayAsTyped() {
        #expect(Renderer.captionText("a **b** c", size: 14).string == "a b c")
        #expect(Renderer.captionText("2 ** 3", size: 14).string == "2 ** 3")
    }
}
