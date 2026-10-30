import Foundation
import Testing
@testable import SNotateCore

struct CaseWalkerTests {
    /// poc-root/poc-sample/ holding the annotated case, the scale case
    /// without a sidecar, a folder of goldens, and a product folder one
    /// level deeper with another annotated case; the annotated case also
    /// has a notated/ folder and assets/.
    private func tree() throws -> (TempFolder, URL) {
        let temp = try TempFolder()
        let product = try temp.folder("poc-root/poc-sample")
        let annotated = product.appendingPathComponent("poc-sample-vm-migrate")
        try FileManager.default.copyItem(at: Fixtures.url("poc-sample-vm-migrate"), to: annotated)
        try FileManager.default.copyItem(at: Fixtures.url("sidecars/poc-sample-vm-migrate.snotate.json"), to: annotated.appendingPathComponent("poc-sample-vm-migrate.snotate.json"))
        try FileManager.default.copyItem(at: Fixtures.url("poc-sample-vm-scale"), to: product.appendingPathComponent("poc-sample-vm-scale"))
        try temp.file("poc-root/poc-sample/golden/x.png")
        let deeper = try temp.folder("poc-root/poc-other/nested")
        try FileManager.default.copyItem(at: annotated, to: deeper.appendingPathComponent("poc-sample-vm-migrate"))
        return (temp, temp.url.appendingPathComponent("poc-root"))
    }

    @Test func casesWithASidecarAreFoundAtAnyDepth() throws {
        let (temp, root) = try tree()
        _ = temp
        let found = CaseWalker.cases(under: root)
        #expect(found.withSidecar.map { $0.pathComponents.suffix(2).joined(separator: "/") } == [
            "nested/poc-sample-vm-migrate",
            "poc-sample/poc-sample-vm-migrate",
        ])
        #expect(found.withoutSidecar.map(\.lastPathComponent) == ["golden", "poc-sample-vm-scale"])
        #expect(!CaseWalker.isCase(root))
        #expect(CaseWalker.isCase(found.withSidecar[0]))
    }

    @Test func headlessExportOfARootExportsEachCaseAndTotals() throws {
        let (temp, root) = try tree()
        _ = temp
        var lines: [String] = []
        #expect(HeadlessExport.run([root.path]) { lines.append($0) } == 0)
        #expect(lines.filter { $0 == "poc-sample-vm-migrate" }.count == 2)
        #expect(lines.last == "\(root.path): 2 cases exported, 2 without a sidecar skipped, 0 failed")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("poc-sample/poc-sample-vm-scale/notated").path))
        var again: [String] = []
        _ = HeadlessExport.run([root.path]) { again.append($0) }
        #expect(again.filter { $0.hasPrefix("  0 written, 7 unchanged") }.count == 2)
    }

    @Test func aCaseThatFailsMakesTheStatusOneAndTheRestStillExport() throws {
        let (temp, root) = try tree()
        _ = temp
        try Data("{".utf8).write(to: root.appendingPathComponent("poc-other/nested/poc-sample-vm-migrate/poc-sample-vm-migrate.snotate.json"))
        var lines: [String] = []
        #expect(HeadlessExport.run([root.path]) { lines.append($0) } == 1)
        #expect(lines.contains { $0.hasPrefix("error: ") && $0.contains("nested/poc-sample-vm-migrate") })
        #expect(lines.last == "\(root.path): 1 case exported, 2 without a sidecar skipped, 1 failed")
    }
}
