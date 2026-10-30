import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct ExporterTests {
    private func notated(_ annotated: AnnotatedCase, _ n: Int) -> URL {
        annotated.folder.appendingPathComponent("notated/\(AnnotatedCase.file(n))")
    }

    private func listing(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func exportWritesEveryStepAndLeavesTheOriginalsAlone() throws {
        let annotated = try AnnotatedCase()
        let before = try listing(annotated.folder)
        let originals = try (0...5).map { try Data(contentsOf: annotated.folder.appendingPathComponent(AnnotatedCase.file($0))) }
        let report = try Exporter.exportCase(try annotated.document())
        #expect(report.written == (0...4).map { "notated/\(AnnotatedCase.file($0))" } + ["md", "yaml"].map { "notated/\(AnnotatedCase.name).\($0)" })
        #expect(report.unchanged.isEmpty)
        #expect(report.removed.isEmpty)
        #expect(report.skipped.isEmpty)
        #expect(report.warnings.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: notated(annotated, 5).path))
        #expect(try listing(annotated.folder) == (before + ["notated"]).sorted())
        #expect(try (0...5).map { try Data(contentsOf: annotated.folder.appendingPathComponent(AnnotatedCase.file($0))) } == originals)
    }

    @Test func annotatedStepsMatchTheirGoldensAndBareStepsTheirCaptures() throws {
        let annotated = try AnnotatedCase()
        _ = try Exporter.exportCase(try annotated.document())
        for n in [0, 2, 4] {
            let image = try #require(Renderer.loadImage(at: notated(annotated, n)))
            try Golden.check(image, String(format: "export-%02d", n))
        }
        #expect(Renderer.loadImage(at: notated(annotated, 2))?.width == 1220)
        for n in [1, 3] {
            let exported = try #require(Renderer.loadImage(at: notated(annotated, n)))
            let original = try #require(Renderer.loadImage(at: annotated.folder.appendingPathComponent(AnnotatedCase.file(n))))
            #expect(Golden.pixels(exported) == Golden.pixels(original))
        }
    }

    @Test func aSecondExportWritesNothing() throws {
        let annotated = try AnnotatedCase()
        let document = try annotated.document()
        _ = try Exporter.exportCase(document)
        let dates = try (0...4).map {
            try FileManager.default.attributesOfItem(atPath: notated(annotated, $0).path)[.modificationDate] as? Date
        }
        let report = try Exporter.exportCase(document)
        #expect(report.written.isEmpty)
        #expect(report.unchanged.count == 7)
        let after = try (0...4).map {
            try FileManager.default.attributesOfItem(atPath: notated(annotated, $0).path)[.modificationDate] as? Date
        }
        #expect(after == dates)
    }

    @Test func staleExportsAreRemovedAndNothingElseIsTouched() throws {
        let annotated = try AnnotatedCase()
        var document = try annotated.document()
        _ = try Exporter.exportCase(document)
        let folder = annotated.folder.appendingPathComponent("notated")
        try Data("keep".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("drafts"), withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("drafts/old.png"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("assets/scap-old.png"))
        document.sidecar.steps[3].excluded = true
        let report = try Exporter.exportCase(document)
        #expect(report.removed == ["notated/assets/scap-old.png", "notated/\(AnnotatedCase.file(3))"])
        #expect(!FileManager.default.fileExists(atPath: notated(annotated, 3).path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("notes.txt").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("drafts/old.png").path))
    }

    @Test func unreadableItemsAndFlaggedStepsAreWarnedAbout() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-scale")
        let base = PixelSize(width: 1600, height: 1000)
        let sidecar = Sidecar(steps: [
            SidecarStep(
                file: "poc-sample-vm-scale-00.png",
                size: base,
                items: [Annotation(json: .object(["type": .string("laser")]), path: "items[0]")]
            ),
            SidecarStep(file: "poc-sample-vm-scale-01.png", size: base),
            SidecarStep(file: "poc-sample-vm-scale-02.png", size: base),
        ])
        try sidecar.encoded().write(to: folder.appendingPathComponent("poc-sample-vm-scale.snotate.json"))
        let report = try Exporter.exportCase(try CaseDocument.load(folder: folder))
        #expect(report.written.count == 5)
        #expect(report.warnings == [
            "steps[0].items[0]: unknown type 'laser'; kept, not drawn",
            "poc-sample-vm-scale-02.png: recorded at 1600 x 1000, image is 1592 x 982; exported unscaled",
        ])
    }

    @Test func oneStepAndTheClipboardUseTheCaseNumbering() throws {
        let annotated = try AnnotatedCase()
        let document = try annotated.document()
        let report = try Exporter.exportStep(AnnotatedCase.file(4), of: document)
        #expect(report.written == ["notated/\(AnnotatedCase.file(4))"])
        #expect(try listing(annotated.folder.appendingPathComponent("notated")) == [AnnotatedCase.file(4)])
        let single = try Data(contentsOf: notated(annotated, 4))
        #expect(try Exporter.pngData(for: AnnotatedCase.file(4), of: document) == single)
        _ = try Exporter.exportCase(document)
        // Its counter is number 4 in the whole case, the same either way.
        #expect(try Data(contentsOf: notated(annotated, 4)) == single)
        #expect(throws: ExportError.excluded(AnnotatedCase.file(5))) {
            try Exporter.exportStep(AnnotatedCase.file(5), of: document)
        }
        #expect(throws: ExportError.unknownStep("nope.png")) {
            try Exporter.pngData(for: "nope.png", of: document)
        }
    }
}

struct ExportCommandTests {
    @Test func exportCommandsAskTheWindowAndRefuseAnExcludedStep() throws {
        var fixture = try EditorFixture()
        #expect(DefaultKeymap.keymap.command(for: try Key.parseSequence("cmd-e")) == .exportCase)
        #expect(DefaultKeymap.keymap.command(for: try Key.parseSequence("cmd-E")) == .exportStep)
        #expect(DefaultKeymap.keymap.command(for: try Key.parseSequence("cmd-C")) == .copyStep)
        #expect(fixture.run(.exportCase) == [.exportCase])
        #expect(fixture.run(.exportStep) == [.exportStep("poc-sample-vm-migrate-00.png")])
        #expect(fixture.run(.copyStep) == [.copyStep("poc-sample-vm-migrate-00.png")])
        fixture.run(.exclude)
        #expect(fixture.run(.exportStep) == [.message("poc-sample-vm-migrate-00.png is excluded from export")])
    }

    @Test func theSummarySaysWhatHappened() {
        var report = ExportReport()
        report.written = ["a", "b"]
        #expect(report.summary == "2 written, 0 unchanged, 0 removed, 0 skipped")
        report.excluded = ["c"]
        report.warnings = ["w"]
        #expect(report.summary == "2 written, 0 unchanged, 0 removed, 0 skipped, 1 excluded, 1 warning")
    }
}
