import Foundation
import Testing
@testable import SNotateCore

struct CaptionTests {
    private let file = "poc-sample-vm-migrate-02.png"
    private let memoName = "poc-sample-vm-migrate.md"

    private func lines(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
    }

    @Test func aMemoReferenceIsTheCaption() throws {
        let fixture = try EditorFixture()
        #expect(fixture.state.captionSource(for: file) == .memo)
        #expect(fixture.state.caption(for: file) == "Choose the target host in the same cluster")
    }

    @Test func settingACaptionRewritesOneLineAndUndoesAndRedoes() throws {
        var fixture = try EditorFixture()
        let before = try #require(fixture.state.document.memo).bytes
        #expect(fixture.run(.setCaption(file, "Pick host-02 in cluster A")) == [.memoChanged])
        let after = try #require(fixture.state.document.memo).bytes
        let changed = zip(lines(before), lines(after)).filter { $0 != $1 }
        #expect(lines(before).count == lines(after).count)
        #expect(changed.map(\.1) == ["- Pick host-02 in cluster A"])
        #expect(fixture.state.undo.undoLabel == "Caption")
        #expect(fixture.run(.undo) == [.sidecarChanged, .memoChanged])
        #expect(fixture.state.document.memo?.bytes == before)
        fixture.run(.redo)
        #expect(fixture.state.caption(for: file) == "Pick host-02 in cluster A")
        #expect(fixture.run(.setCaption(file, "Pick host-02 in cluster A")).isEmpty)
    }

    @Test func anEmptyCaptionIsThePlaceholderAndALineBreakIsRefused() throws {
        var fixture = try EditorFixture()
        fixture.run(.setCaption(file, "  "))
        #expect(fixture.state.document.memo?.entry(for: file)?.caption == Memo.placeholder)
        #expect(fixture.state.caption(for: file) == "")
        #expect(fixture.run(.setCaption(file, "a\nb")) == [.message("A caption is one line")])
    }

    @Test func withoutAMemoTheSidecarHoldsTheCaption() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        try FileManager.default.removeItem(at: folder.appendingPathComponent(memoName))
        var state = EditorState(document: try CaseDocument.load(folder: folder))
        #expect(state.captionSource(for: file) == .sidecar)
        #expect(Dispatcher.apply(Invocation(.setCaption(file, "Pick a host")), to: &state) == [.sidecarChanged])
        #expect(state.document.sidecar.steps.first { $0.file == file }?.caption == "Pick a host")
        #expect(state.caption(for: file) == "Pick a host")
        Dispatcher.apply(Invocation(.setCaption(file, "")), to: &state)
        #expect(state.document.sidecar.steps.first { $0.file == file }?.caption == nil)
    }

    @Test func anUnreadableMemoMakesCaptionsReadOnly() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        try Data([0xFF, 0xFE, 0x00]).write(to: folder.appendingPathComponent(memoName))
        var state = EditorState(document: try CaseDocument.load(folder: folder))
        #expect(state.captionSource(for: file) == .readOnly("the memo is not UTF-8 text"))
        #expect(Dispatcher.apply(Invocation(.setCaption(file, "x")), to: &state) == [.message("Captions are read-only: the memo is not UTF-8 text")])
    }

    @Test func sidecarCaptionsMoveIntoTheMemoOnlyWhereItHasNone() throws {
        let memo = try Memo(data: Data("""
            - description

            ![](a.png)

            ![](b.png)

            - Already written

            ![](c.png)

            - Same

            ![](d.png)

            """.utf8))
        var sidecar = Sidecar(steps: ["a.png", "b.png", "c.png", "d.png", "e.png"].map { SidecarStep(file: $0) })
        for (index, caption) in ["Open the list", "Pick the VM", "Something else", "Same", "Not in the memo"].enumerated() {
            sidecar.steps[index].caption = caption
        }
        let result = try #require(CaptionMigration.migrate(memo: memo, sidecar: sidecar))
        #expect(result.memo.entry(for: "a.png")?.caption == "Open the list")
        #expect(result.memo.entry(for: "b.png")?.caption == "Pick the VM")
        #expect(result.memo.entry(for: "c.png")?.caption == "Already written")
        #expect(result.sidecar.steps.map(\.caption) == [nil, nil, "Something else", nil, "Not in the memo"])
        #expect(result.kept == ["c.png"])
        #expect(CaptionMigration.migrate(memo: result.memo, sidecar: Sidecar(steps: [])) == nil)
    }
}

@MainActor
struct MemoWriteTests {
    private let file = "poc-sample-vm-migrate-02.png"

    private func editor(_ temp: TempFolder) throws -> (CaseEditor, URL) {
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        let session = CaseSession(document: try CaseDocument.load(folder: folder), saveDelay: .milliseconds(20), watchDebounce: .milliseconds(50))
        return (CaseEditor(session: session), folder.appendingPathComponent("poc-sample-vm-migrate.md"))
    }

    @Test func aCaptionReachesTheFileAtOnceWithoutAReload() async throws {
        let temp = try TempFolder()
        let (editor, url) = try editor(temp)
        var reloads = 0
        editor.session.onReload = { reloads += 1 }
        editor.perform(.setCaption(file, "Pick host-02"))
        #expect(try Memo.read(url).entry(for: file)?.caption == "Pick host-02")
        try await Task.sleep(for: .milliseconds(400))
        #expect(reloads == 0)
        #expect(editor.state.undo.count == 1)
        editor.perform(.undo)
        #expect(try Memo.read(url).entry(for: file)?.caption == "Choose the target host in the same cluster")
    }

    @Test func aMemoChangedElsewhereIsNeverOverwritten() throws {
        let temp = try TempFolder()
        let (editor, url) = try editor(temp)
        var messages: [String] = []
        editor.onMessage = { messages.append($0) }
        let outside = Data("# edited elsewhere\n\n- Mine\n\n![](poc-sample-vm-migrate-02.png)\n".utf8)
        try outside.write(to: url)
        editor.perform(.setCaption(file, "Pick host-02"))
        #expect(try Data(contentsOf: url) == outside)
        #expect(messages == ["Caption not saved: the memo changed on disk since it was read; reloaded from disk"])
        #expect(editor.state.caption(for: file) == "Mine")
    }

    @Test func migrationRunsWhenTheCaseIsShown() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        let url = folder.appendingPathComponent("poc-sample-vm-migrate.md")
        var memo = try String(contentsOf: url, encoding: .utf8)
        memo = memo.replacingOccurrences(of: "- Choose the target host in the same cluster\n\n", with: "")
        try Data(memo.utf8).write(to: url)
        var document = try CaseDocument.load(folder: folder)
        let index = try #require(document.sidecar.steps.firstIndex { $0.file == file })
        document.sidecar.steps[index].caption = "Choose host-02"
        let editor = CaseEditor(session: CaseSession(document: document, saveDelay: .milliseconds(10)))
        editor.migrateCaptions()
        #expect(try Memo.read(url).entry(for: file)?.caption == "Choose host-02")
        #expect(editor.state.document.sidecar.steps[index].caption == nil)
        #expect(editor.state.undo.count == 0)
    }
}
