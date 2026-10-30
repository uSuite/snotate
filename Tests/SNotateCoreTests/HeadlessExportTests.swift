import Foundation
import Testing
@testable import SNotateCore

struct HeadlessExportTests {
    private func run(_ arguments: [String]) -> (code: Int32, lines: [String]) {
        var lines: [String] = []
        let code = HeadlessExport.run(arguments) { lines.append($0) }
        return (code, lines)
    }

    @Test func exportsEachCaseAndSaysWhatItDid() throws {
        let annotated = try AnnotatedCase()
        let first = run([annotated.folder.path])
        #expect(first.code == 0)
        #expect(first.lines.first == AnnotatedCase.name)
        #expect(first.lines.contains("  wrote notated/\(AnnotatedCase.file(0))"))
        #expect(first.lines.last == "  7 written, 0 unchanged, 0 removed, 0 skipped, 1 excluded")
        let second = run([annotated.folder.path])
        #expect(second.code == 0)
        #expect(second.lines.last == "  0 written, 7 unchanged, 0 removed, 0 skipped, 1 excluded")
        #expect(!second.lines.contains { $0.hasPrefix("  wrote") })
    }

    @Test func theConfigFolderNameIsUsedAndItsProblemsAreWarnings() throws {
        let annotated = try AnnotatedCase()
        var settings = Settings()
        settings.config.notatedDir = "evidence"
        settings.issues = ["config line 3: unknown option 'colour'"]
        var lines: [String] = []
        let code = HeadlessExport.run([annotated.folder.path], settings: settings) { lines.append($0) }
        #expect(code == 0)
        #expect(lines.first == "warning: config line 3: unknown option 'colour'")
        #expect(lines.contains("  wrote evidence/\(AnnotatedCase.file(0))"))
        #expect(!FileManager.default.fileExists(atPath: annotated.folder.appendingPathComponent("notated").path))
    }

    @Test func excludedStepsAreListedForDeletion() throws {
        let annotated = try AnnotatedCase()
        let result = run([annotated.folder.path])
        // The annotated fixture excludes step 05.
        #expect(result.lines.contains("  excluded \(AnnotatedCase.file(5))"))
    }

    @Test func aFileInsideACaseExportsThatCase() throws {
        let annotated = try AnnotatedCase()
        let result = run([annotated.folder.appendingPathComponent(AnnotatedCase.file(2)).path])
        #expect(result.code == 0)
        #expect(result.lines.last == "  7 written, 0 unchanged, 0 removed, 0 skipped, 1 excluded")
    }

    @Test func refusalsAreErrorsAndTheOtherCasesStillExport() throws {
        let broken = try AnnotatedCase()
        try Data("<<<<<<< HEAD\n".utf8).write(to: broken.folder.appendingPathComponent("\(AnnotatedCase.name).snotate.json"))
        let good = try AnnotatedCase()
        let result = run([broken.folder.path, "/nonexistent/poc-x-y-z", good.folder.path])
        #expect(result.code == 1)
        #expect(result.lines.filter { $0.hasPrefix("error: ") }.count == 2)
        #expect(result.lines.first { $0.hasPrefix("error: ") }?.contains("sidecar cannot be read") == true)
        #expect(result.lines.last == "  7 written, 0 unchanged, 0 removed, 0 skipped, 1 excluded")
        #expect(FileManager.default.fileExists(atPath: good.folder.appendingPathComponent("notated").path))
        #expect(!FileManager.default.fileExists(atPath: broken.folder.appendingPathComponent("notated").path))
    }

    /// A typo in a case name under a real folder must not open that folder
    /// as the case.
    @Test func aPathThatDoesNotExistIsAnError() throws {
        let annotated = try AnnotatedCase()
        let typo = annotated.folder.appendingPathComponent("poc-no-such-case").path
        let result = run([typo])
        #expect(result.code == 1)
        #expect(result.lines == ["error: \(typo): no such file or folder"])
        #expect(!FileManager.default.fileExists(atPath: annotated.folder.appendingPathComponent("notated").path))
    }

    @Test func noFoldersIsAUsageError() {
        let result = run([])
        #expect(result.code == 2)
        #expect(result.lines == ["usage: sNotate --export <case-folder or poc-root>..."])
    }
}
