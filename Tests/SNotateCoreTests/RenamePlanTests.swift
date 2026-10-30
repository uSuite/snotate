import Foundation
import Testing
@testable import SNotateCore

struct RenamePlanTests {
    private let caseID = "poc-sample-vm-migrate"

    /// The sample case as it is before the evidence script: `scap-` names,
    /// no memo.
    private func captured(_ temp: TempFolder) throws -> URL {
        let folder = try temp.copy(fixture: caseID)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(caseID + ".md"))
        for n in 0..<6 {
            try FileManager.default.moveItem(
                at: folder.appendingPathComponent(String(format: "\(caseID)-%02d.png", n)),
                to: folder.appendingPathComponent(String(format: "scap-2026-10-22-1522%02d.png", n))
            )
        }
        return folder
    }

    private func pairs(_ plan: RenamePlan) -> [String] {
        plan.renames.map { "\($0.from) -> \($0.to)" }
    }

    @Test func withoutAMemoEveryCaptureIsNumberedInStoryOrder() throws {
        let temp = try TempFolder()
        var document = try CaseDocument.load(folder: try captured(temp))
        document.sidecar.steps.swapAt(0, 1)
        document.sidecar.steps[3].excluded = true
        let plan = RenamePlan(document: document)
        #expect(plan.blocked.isEmpty)
        #expect(pairs(plan) == [
            "scap-2026-10-22-152201.png -> \(caseID)-00.png",
            "scap-2026-10-22-152200.png -> \(caseID)-01.png",
            "scap-2026-10-22-152202.png -> \(caseID)-02.png",
            "scap-2026-10-22-152204.png -> \(caseID)-03.png",
            "scap-2026-10-22-152205.png -> \(caseID)-04.png",
        ])
        #expect(plan.kept == [RenamePlan.Kept(file: "scap-2026-10-22-152203.png", reason: "excluded: delete it before renaming")])
    }

    @Test func numberedCapturesAreRenumberedOnlyWhileThereIsNoMemo() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: caseID)
        var document = try CaseDocument.load(folder: folder)
        document.sidecar.steps.swapAt(0, 1)
        #expect(pairs(RenamePlan(document: document)).isEmpty)
        #expect(RenamePlan(document: document).outOfOrder == ["\(caseID)-00.png"])
        try FileManager.default.removeItem(at: folder.appendingPathComponent(caseID + ".md"))
        document = try CaseDocument.load(folder: folder)
        document.sidecar.steps.swapAt(0, 1)
        let plan = RenamePlan(document: document)
        #expect(pairs(plan) == ["\(caseID)-01.png -> \(caseID)-00.png", "\(caseID)-00.png -> \(caseID)-01.png"])
    }

    @Test func withAMemoNewCapturesFollowTheHighestNumberUnlessReferenced() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: caseID)
        try Data([0]).write(to: folder.appendingPathComponent("scap-2026-10-22-160000.png"))
        try FileManager.default.copyItem(
            at: folder.appendingPathComponent(caseID + "-01.png"),
            to: folder.appendingPathComponent("scap-2026-10-22-170000.png")
        )
        let memo = folder.appendingPathComponent(caseID + ".md")
        var text = try String(contentsOf: memo, encoding: .utf8)
        text += "\n- Later\n\n![](scap-2026-10-22-160000.png)\n"
        try Data(text.utf8).write(to: memo)
        let plan = RenamePlan(document: try CaseDocument.load(folder: folder))
        #expect(pairs(plan) == ["scap-2026-10-22-170000.png -> \(caseID)-06.png"])
        #expect(plan.kept.contains(RenamePlan.Kept(file: "scap-2026-10-22-160000.png", reason: "the memo references it")))
        #expect(plan.outOfOrder.isEmpty)
    }

    @Test func aNameHeldByAnExcludedCaptureBlocksThePlan() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: caseID)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(caseID + ".md"))
        var document = try CaseDocument.load(folder: folder)
        document.sidecar.steps[0].excluded = true
        let plan = RenamePlan(document: document)
        #expect(plan.blocked == ["\(caseID)-00.png is taken by a capture the plan leaves alone; delete or rename it first"])
        #expect(!plan.canApply)
    }

    @Test func applyingSwapsNamesAndTheSidecarFollows() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: caseID)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(caseID + ".md"))
        var document = try CaseDocument.load(folder: folder)
        let zero = try Data(contentsOf: folder.appendingPathComponent(caseID + "-00.png"))
        document.sidecar.steps.swapAt(0, 1)
        document.sidecar.steps[1].caption = "was zero"
        let plan = RenamePlan(document: document)
        let sidecar = try plan.apply(in: folder, sidecar: document.sidecar)
        #expect(try Data(contentsOf: folder.appendingPathComponent(caseID + "-01.png")) == zero)
        #expect(sidecar.steps.map(\.file).prefix(2) == ["\(caseID)-00.png", "\(caseID)-01.png"])
        #expect(sidecar.steps[1].caption == "was zero")
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".snotate-rename") }
        #expect(left.isEmpty)
    }

    @Test func aFileAppearingAtATargetStopsTheApplyBeforeAnyRename() throws {
        let temp = try TempFolder()
        let folder = try captured(temp)
        let document = try CaseDocument.load(folder: folder)
        let plan = RenamePlan(document: document)
        try Data([1]).write(to: folder.appendingPathComponent(caseID + "-03.png"))
        #expect(throws: RenamePlan.Failure(description: "\(caseID)-03.png already exists")) {
            try plan.apply(in: folder, sidecar: document.sidecar)
        }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("scap-2026-10-22-152200.png").path))
    }

    @Test func widthGrowsAtAHundredAsTheScriptDoes() {
        #expect(RenamePlan.width(100) == 2)
        #expect(RenamePlan.width(101) == 3)
        #expect(RenamePlan.name("c", 7, width: 3, of: "x.PNG") == "c-007.png")
    }
}

@MainActor
struct RenamePlanEditorTests {
    @Test func theEditorAppliesThePlanAndReloadsWithoutHistory() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("poc-sample-vm-migrate.md"))
        let editor = CaseEditor(session: CaseSession(document: try CaseDocument.load(folder: folder), saveDelay: .milliseconds(10)))
        editor.perform(.moveStepLater)
        #expect(editor.state.undo.count == 1)
        try editor.applyRenamePlan(RenamePlan(document: editor.state.document))
        #expect(editor.state.undo.count == 0)
        #expect(editor.state.document.steps.map(\.file).prefix(2) == ["poc-sample-vm-migrate-00.png", "poc-sample-vm-migrate-01.png"])
        #expect(RenamePlan(document: editor.state.document).renames.isEmpty)
        let saved = try Sidecar.decode(Data(contentsOf: editor.session.document.sidecarURL))
        #expect(saved.steps.map(\.file).prefix(2) == ["poc-sample-vm-migrate-00.png", "poc-sample-vm-migrate-01.png"])
    }
}
