import Foundation
import ImageIO
import Testing
@testable import SNotateCore

struct InsertStepTests {
    private let date = Date(timeIntervalSince1970: 1_793_000_000)
    private let fixture = "poc-sample-vm-migrate"

    private func stem(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "snotate-" + formatter.string(from: date)
    }

    @Test func filesAreCopiedByteForByteUnderFreeProvisionalNames() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: fixture)
        let source = Fixtures.url("\(fixture)/\(fixture)-02.png")
        let names = try InsertStep.copy([.file(source), .file(source)], into: folder, date: date)
        #expect(names == ["\(stem(date)).png", "\(stem(date))-1.png"])
        #expect(try Data(contentsOf: folder.appendingPathComponent(names[0])) == Data(contentsOf: source))
        let again = try InsertStep.copy([.file(source)], into: folder, date: date)
        #expect(again == ["\(stem(date))-2.png"])
    }

    @Test func otherImagesAndPastedDataBecomePNG() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: fixture)
        let image = try #require(Renderer.loadImage(at: Fixtures.url("\(fixture)/\(fixture)-01.png")))
        let tiff = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(tiff, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        let tiffURL = temp.url.appendingPathComponent("shot.tiff")
        try (tiff as Data).write(to: tiffURL)
        let names = try InsertStep.copy([.file(tiffURL), .data(tiff as Data)], into: folder, date: date)
        #expect(names.allSatisfy { $0.hasSuffix(".png") })
        #expect(Renderer.loadImage(at: folder.appendingPathComponent(names[1]))?.width == image.width)
        let text = temp.url.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        #expect(throws: InsertStep.Failure(description: "notes.txt is not an image")) {
            try InsertStep.copy([.file(text)], into: folder, date: date)
        }
    }

    @Test func newStepsArePlacedAtTheGap() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: fixture)
        let names = try InsertStep.copy([.file(Fixtures.url("\(fixture)/\(fixture)-02.png"))], into: folder, date: date)
        let document = try CaseDocument.load(folder: folder)
        var trimmed = document
        trimmed.sidecar.steps.removeAll { names.contains($0.file) }
        let sidecar = InsertStep.placed(names, at: 2, in: trimmed)
        #expect(sidecar.steps.map(\.file)[1...3] == ["\(fixture)-01.png", names[0], "\(fixture)-02.png"])
        #expect(sidecar.steps[2].size == PixelSize(width: 1600, height: 1000))
        #expect(InsertStep.placed(names, at: 6, in: trimmed).steps.last?.file == names[0])
    }
}

@MainActor
struct InsertStepEditorTests {
    @Test func theEditorInsertsAtTheGapAndMakesItCurrent() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        let editor = CaseEditor(session: CaseSession(document: try CaseDocument.load(folder: folder), saveDelay: .milliseconds(10)))
        let names = try editor.insertSteps([.file(Fixtures.url("poc-sample-vm-migrate/poc-sample-vm-migrate-03.png"))], at: 1)
        #expect(editor.state.document.steps.map(\.file)[0...2] == ["poc-sample-vm-migrate-00.png", names[0], "poc-sample-vm-migrate-01.png"])
        #expect(editor.state.current == 1)
        let saved = try Sidecar.decode(Data(contentsOf: editor.session.document.sidecarURL))
        #expect(saved.steps[1].file == names[0])
        let reread = try CaseDocument.load(folder: folder)
        #expect(reread.steps[1].file == names[0])
    }
}
