import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

/// SN-605: what the disk can do to an open case, and captures that are not
/// what their names say.
@MainActor
struct HostileTests {
    private let migrate = "poc-sample-vm-migrate"
    private let counter = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))

    private func editor(_ folder: URL) throws -> (CaseEditor, Messages) {
        let editor = CaseEditor(session: CaseSession(
            document: try CaseDocument.load(folder: folder),
            saveDelay: .seconds(60),
            watchDebounce: .seconds(60)
        ))
        let messages = Messages()
        editor.onMessage = { messages.list.append($0) }
        return (editor, messages)
    }

    final class Messages {
        var list: [String] = []
    }

    @Test func unknownKeysAndTypesSurviveAnEdit() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        let sidecarURL = folder.appendingPathComponent("\(migrate).snotate.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.url("sidecars/\(migrate).snotate.json"))) as! [String: Any]
        var steps = json["steps"] as! [[String: Any]]
        var items = steps[0]["items"] as! [[String: Any]]
        items[0]["pulse"] = true
        items.append(["type": "sparkle", "at": [5, 5]])
        steps[0]["items"] = items
        steps[0]["timing"] = 1.5
        json["steps"] = steps
        json["future"] = ["camera": "ease"]
        try JSONSerialization.data(withJSONObject: json).write(to: sidecarURL)
        let (editor, _) = try editor(folder)
        editor.perform(.add(counter))
        editor.close()
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: sidecarURL)) as! [String: Any]
        let savedSteps = saved["steps"] as! [[String: Any]]
        let savedItems = savedSteps[0]["items"] as! [[String: Any]]
        #expect((saved["future"] as? [String: String]) == ["camera": "ease"])
        #expect(savedSteps[0]["timing"] as? Double == 1.5)
        #expect(savedItems[0]["pulse"] as? Bool == true)
        #expect(savedItems.contains { $0["type"] as? String == "sparkle" })
        #expect(savedItems.count == items.count + 1)
    }

    @Test func aFailedSaveIsSaidOnceAndSoIsItsRecovery() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        let (editor, messages) = try editor(folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        editor.perform(.add(counter))
        editor.close()
        editor.perform(.add(Annotation(shape: .counter(at: CGPoint(x: 20, y: 20)))))
        editor.close()
        #expect(messages.list.count == 1)
        #expect(messages.list.first?.hasPrefix("Not saved: ") == true)
        #expect(editor.session.saveError != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        editor.close()
        #expect(messages.list.last == "Saved")
        let saved = try Sidecar.decode(Data(contentsOf: editor.session.document.sidecarURL))
        #expect(saved.steps[0].items.count == 2)
    }

    @Test func aFolderThatGoesAndComesBackIsSaidOnceEach() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        let (editor, messages) = try editor(folder)
        try FileManager.default.removeItem(at: folder)
        editor.session.reload()
        editor.session.reload()
        #expect(messages.list == ["The case folder is gone; changes cannot be saved"])
        #expect(editor.state.document.steps.count == 6)
        try FileManager.default.copyItem(at: Fixtures.url(migrate), to: folder)
        editor.session.reload()
        #expect(messages.list.last == "The case folder is back")
    }

    /// A disk ejected under the window may never wake the folder watch; the
    /// next save finds the folder gone and says that, not a file error.
    @Test func aSaveIntoAVanishedFolderSaysTheFolderIsGone() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        let (editor, messages) = try editor(folder)
        editor.perform(.add(counter))
        try FileManager.default.removeItem(at: folder)
        editor.close()
        editor.close()
        #expect(messages.list == ["The case folder is gone; changes cannot be saved"])
        #expect(editor.session.saveError != nil)
    }

    @Test func aCaptureThatGoesMissingIsSaidAndItsAnnotationsKept() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        try FileManager.default.copyItem(
            at: Fixtures.url("sidecars/\(migrate).snotate.json"),
            to: folder.appendingPathComponent("\(migrate).snotate.json")
        )
        let (editor, messages) = try editor(folder)
        editor.reportMissing()
        #expect(messages.list.isEmpty)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("\(migrate)-00.png"))
        editor.session.reload()
        #expect(messages.list == ["\(migrate)-00.png is missing; the sidecar keeps it"])
        #expect(editor.state.document.steps.count == 5)
        #expect(editor.state.document.sidecar.steps[0].items.count == 3)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("\(migrate)-01.png"))
        editor.session.reload()
        #expect(messages.list.last == "\(migrate)-01.png is missing; the sidecar keeps it")
        editor.reportMissing()
        #expect(messages.list.last == "2 captures are missing; the sidecar keeps them")
    }

    @Test func capturesThatCannotBeDecodedAreSkippedByName() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("poc-broken")
        let context = Renderer.bitmap(width: 40, height: 30)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let png = Renderer.pngData(context.makeImage()!)
        try png.write(to: folder.appendingPathComponent("poc-broken-00.png"))
        try Data().write(to: folder.appendingPathComponent("poc-broken-01.png"))
        try Data("not a PNG\n".utf8).write(to: folder.appendingPathComponent("poc-broken-02.png"))
        let document = try CaseDocument.load(folder: folder)
        #expect(document.steps.map(\.file) == ["poc-broken-00.png", "poc-broken-01.png", "poc-broken-02.png"])
        let report = try Exporter.exportCase(document)
        #expect(report.written == ["notated/poc-broken-00.png", "notated/poc-broken.md", "notated/poc-broken.yaml"])
        #expect(report.skipped.map(\.file) == ["poc-broken-01.png", "poc-broken-02.png"])
        #expect(report.skipped.allSatisfy { $0.reason == "image cannot be decoded" })
        var typst = ExportOptions()
        typst.typst = true
        _ = try Exporter.exportCase(document, options: typst)
        let fragment = try String(contentsOf: folder.appendingPathComponent("notated/poc-broken.typ"), encoding: .utf8)
        #expect(fragment.contains("#shot(image(\"poc-broken-00.png\"))"))
        #expect(!fragment.contains("poc-broken-01") && !fragment.contains("poc-broken-02"))
    }
}
