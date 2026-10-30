import Foundation
import Testing
@testable import SNotateCore

/// The migrate case with the committed annotated sidecar, in a temp copy.
struct AnnotatedCase {
    static let name = "poc-sample-vm-migrate"
    let temp: TempFolder
    let folder: URL

    init() throws {
        temp = try TempFolder()
        folder = try temp.copy(fixture: Self.name)
        try FileManager.default.copyItem(
            at: Fixtures.url("sidecars/\(Self.name).snotate.json"),
            to: folder.appendingPathComponent("\(Self.name).snotate.json")
        )
    }

    func document() throws -> CaseDocument {
        try CaseDocument.load(folder: folder)
    }

    static func file(_ n: Int) -> String {
        String(format: "\(name)-%02d.png", n)
    }
}

struct ExportPlanTests {
    @Test func theSidecarFixtureIsCanonicalAndReadable() throws {
        let data = try Data(contentsOf: Fixtures.url("sidecars/poc-sample-vm-migrate.snotate.json"))
        let sidecar = try Sidecar.decode(data)
        #expect(sidecar.encoded() == data)
        #expect(sidecar.itemIssues.isEmpty)
    }

    @Test func everyStepButTheExcludedOneIsATarget() throws {
        let annotated = try AnnotatedCase()
        let plan = try ExportPlan(document: try annotated.document())
        #expect(plan.folder.path == annotated.folder.appendingPathComponent("notated").path)
        #expect(plan.targets.map(\.file) == (0...4).map(AnnotatedCase.file))
        #expect(plan.targets[2].relative == "notated/\(AnnotatedCase.file(2))")
        #expect(plan.targets[2].output == annotated.folder.appendingPathComponent("notated/\(AnnotatedCase.file(2))"))
        #expect(plan.skipped.isEmpty)
    }

    @Test func outputsMirrorAssetsAndAlwaysEndInPNG() {
        #expect(ExportPlan.outputPath(for: "poc-x-y-z-03.png") == "poc-x-y-z-03.png")
        #expect(ExportPlan.outputPath(for: "assets/scap-2026-10-22-160218.png") == "assets/scap-2026-10-22-160218.png")
        #expect(ExportPlan.outputPath(for: "shot.JPG") == "shot.png")
        #expect(ExportPlan.outputPath(for: "assets/shot.heic") == "assets/shot.png")
    }

    @Test func clashingAndMissingStepsAreSkipped() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("poc-demo-vm-stop")
        try temp.file("poc-demo-vm-stop/shot.png")
        try temp.file("poc-demo-vm-stop/shot.jpg")
        try temp.file("poc-demo-vm-stop/other.png")
        var document = try CaseDocument.load(folder: folder)
        document.sidecar.steps.append(SidecarStep(file: "gone.png"))
        let plan = try ExportPlan(document: document)
        #expect(plan.targets.map(\.file) == ["other.png"])
        #expect(Set(plan.skipped) == [
            ExportPlan.Skipped(file: "shot.jpg", reason: "same output as shot.png"),
            ExportPlan.Skipped(file: "shot.png", reason: "same output as shot.jpg"),
            ExportPlan.Skipped(file: "gone.png", reason: "image is missing"),
        ])
    }

    @Test func theFolderNameCannotReachTheOriginals() throws {
        let document = try AnnotatedCase().document()
        for name in ["", ".", "..", "a/b", "assets", "/tmp"] {
            #expect(throws: ExportError.badFolder(name)) {
                try ExportPlan(document: document, folderName: name)
            }
        }
        #expect(try ExportPlan(document: document, folderName: "out").folder.lastPathComponent == "out")
    }

    @Test func anUnreadableSidecarRefusesTheExport() throws {
        let annotated = try AnnotatedCase()
        try Data("<<<<<<< HEAD\n".utf8).write(to: annotated.folder.appendingPathComponent("\(AnnotatedCase.name).snotate.json"))
        let document = try annotated.document()
        #expect {
            try ExportPlan(document: document)
        } throws: { error in
            guard case ExportError.readOnly = error else {
                return false
            }
            return true
        }
    }
}
