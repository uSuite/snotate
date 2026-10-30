import Foundation
import Testing
@testable import SNotateCore

struct CaseDocumentTests {
    private let migrate = "poc-sample-vm-migrate"

    private func names(_ prefix: String, _ numbers: [Int]) -> [String] {
        numbers.map { String(format: "\(prefix)-%02d.png", $0) }
    }

    @Test func opensTheSampleCaseInEvidenceOrderWithoutWriting() throws {
        let folder = Fixtures.url(migrate)
        let document = try CaseDocument.load(folder: folder)
        #expect(document.caseID == migrate)
        #expect(document.pocCase?.product == "sample")
        #expect(document.pocCase?.action == "migrate")
        #expect(document.memoURL == folder.appendingPathComponent("\(migrate).md"))
        #expect(document.sidecarURL == folder.appendingPathComponent("\(migrate).snotate.json"))
        #expect(document.steps.map(\.file) == names(migrate, Array(0...5)))
        #expect(document.steps.allSatisfy { $0.size == PixelSize(width: 1600, height: 1000) && $0.scale == .match })
        #expect(document.steps[2].url == folder.appendingPathComponent("\(migrate)-02.png"))
        #expect(document.missing.isEmpty)
        #expect(document.sidecarIssue == nil)
        #expect(!FileManager.default.fileExists(atPath: document.sidecarURL.path))
    }

    @Test func renamedStepsComeFirstByNumberThenCapturesByName() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("poc-demo-vm-stop")
        for name in [
            "poc-demo-vm-stop-10.png",
            "poc-demo-vm-stop-2.png",
            "scap-2026-10-22-160246.png",
            "scap-2026-10-22-160218.png",
            "poc-demo-vm-stop.md",
            "notes.txt",
            ".hidden.png",
            "notated/poc-demo-vm-stop-2.png",
        ] {
            try temp.file("poc-demo-vm-stop/\(name)")
        }
        let document = try CaseDocument.load(folder: folder)
        #expect(document.steps.map(\.file) == [
            "poc-demo-vm-stop-2.png",
            "poc-demo-vm-stop-10.png",
            "scap-2026-10-22-160218.png",
            "scap-2026-10-22-160246.png",
        ])
        #expect(document.steps.allSatisfy { $0.size == nil && $0.scale == nil })
    }

    @Test func capturesInAnAssetsFolderAreStepsWithTheirRelativePath() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("poc-demo-app-workspace-rules")
        try temp.file("poc-demo-app-workspace-rules/assets/scap-2026-10-22-160246.png")
        try temp.file("poc-demo-app-workspace-rules/assets/scap-2026-10-22-160218.png")
        try temp.file("poc-demo-app-workspace-rules/poc-demo-app-workspace-rules.md")
        let document = try CaseDocument.load(folder: folder)
        #expect(document.steps.map(\.file) == [
            "assets/scap-2026-10-22-160218.png",
            "assets/scap-2026-10-22-160246.png",
        ])
        #expect(document.steps[0].url == folder.appendingPathComponent("assets/scap-2026-10-22-160218.png"))
    }

    @Test func sidecarOrderWinsNewFilesFollowTheirPredecessorMissingAreKept() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        let file = names(migrate, Array(0...5))
        let sidecar = Sidecar(steps: [
            SidecarStep(file: file[3], size: PixelSize(width: 1600, height: 1000)),
            SidecarStep(file: file[1], size: PixelSize(width: 1600, height: 1000), excluded: true),
            SidecarStep(file: "gone.png", size: PixelSize(width: 1600, height: 1000)),
            SidecarStep(file: file[0], size: PixelSize(width: 1600, height: 1000)),
        ])
        let url = folder.appendingPathComponent("\(migrate).snotate.json")
        try sidecar.encoded().write(to: url)
        let document = try CaseDocument.load(folder: folder)
        #expect(document.sidecar.steps.map(\.file) == [file[3], file[4], file[5], file[1], file[2], "gone.png", file[0]])
        #expect(document.steps.map(\.file) == [file[3], file[4], file[5], file[1], file[2], file[0]])
        #expect(document.steps.map(\.excluded) == [false, false, false, true, false, false])
        #expect(document.missing == ["gone.png"])
        #expect(document.added == [file[4], file[5], file[2]])
        #expect(try Data(contentsOf: url) == sidecar.encoded())
    }

    @Test func aMissingSizeIsFilledInMemoryOnly() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        let url = folder.appendingPathComponent("\(migrate).snotate.json")
        let old = Data(#"{"steps": [{"file": "poc-sample-vm-migrate-00.png"}], "version": 1}"#.utf8)
        try old.write(to: url)
        let document = try CaseDocument.load(folder: folder)
        #expect(document.sidecar.steps[0].size == PixelSize(width: 1600, height: 1000))
        #expect(document.steps[0].scale == .match)
        #expect(try Data(contentsOf: url) == old)
    }

    @Test func recordedSizesAreComparedWithTheImages() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-scale")
        let base = PixelSize(width: 1600, height: 1000)
        let sidecar = Sidecar(steps: names("poc-sample-vm-scale", [0, 1, 2]).map { SidecarStep(file: $0, size: base) })
        try sidecar.encoded().write(to: folder.appendingPathComponent("poc-sample-vm-scale.snotate.json"))
        let document = try CaseDocument.load(folder: folder)
        #expect(document.steps.map(\.scale) == [
            .match,
            .scaled(2),
            .mismatch(recorded: base, actual: PixelSize(width: 1592, height: 982)),
        ])
    }

    @Test func anInvalidSidecarIsReportedAndLeftAlone() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        let url = folder.appendingPathComponent("\(migrate).snotate.json")
        let conflict = Data("<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> other\n".utf8)
        try conflict.write(to: url)
        let document = try CaseDocument.load(folder: folder)
        guard case .invalidJSON = document.sidecarIssue else {
            Issue.record("expected invalidJSON, got \(String(describing: document.sidecarIssue))")
            return
        }
        #expect(document.steps.count == 6)
        #expect(try Data(contentsOf: url) == conflict)
    }

    @Test func openingAFileOpensItsCaseAtThatStep() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("poc-demo-app-workspace-rules")
        let capture = try temp.file("poc-demo-app-workspace-rules/assets/scap-2026-10-22-160246.png")
        try temp.file("poc-demo-app-workspace-rules/assets/scap-2026-10-22-160218.png")
        let opened = try CaseDocument.open(capture)
        #expect(opened.document.folder == folder)
        #expect(opened.selected == 1)
        let step = Fixtures.url("\(migrate)/\(migrate)-03.png")
        #expect(try CaseDocument.open(step).selected == 3)
        let whole = try CaseDocument.open(Fixtures.url(migrate))
        #expect(whole.selected == nil)
        #expect(whole.document.steps.count == 6)
    }

    @Test func theMemoIsReadWithTheCase() throws {
        let document = try CaseDocument.load(folder: Fixtures.url(migrate))
        #expect(document.memoIssue == nil)
        #expect(document.steps.map { document.memo?.entry(for: $0.file)?.caption } == [
            "Open the VM list and pick the running VM to migrate",
            "Open **Actions** > **Migrate** on the VM",
            "Choose the target host in the same cluster",
            "Confirm the migration in the dialog",
            "The task list shows the migration running",
            "The VM is Running on the target host",
        ])
    }

    @Test func anUnreadableMemoIsReportedAndTheCaseStillOpens() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        try Data([0x2d, 0x20, 0xff, 0x0a]).write(to: folder.appendingPathComponent("\(migrate).md"))
        let document = try CaseDocument.load(folder: folder)
        #expect(document.memo == nil)
        #expect(document.memoIssue == .notUTF8)
        #expect(document.memoURL != nil)
        #expect(document.steps.count == 6)
    }

    @Test func originalsAreNeverWritten() throws {
        let folder = Fixtures.url(migrate)
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        _ = try CaseDocument.load(folder: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == before)
    }
}
