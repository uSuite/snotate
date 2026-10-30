import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct MemoRemovalTests {
    private func memo(_ text: String) throws -> Memo {
        try Memo(data: Data(text.utf8))
    }

    private func text(_ memo: Memo) -> String {
        String(decoding: memo.bytes, as: UTF8.self)
    }

    private let script = "# case\n\n- one\n\n![case-00](case-00.png)\n\n- two\n\n![case-01](case-01.png)\n\n- three\n\n![case-02](case-02.png)\n"

    @Test func aMiddleBlockLeavesWithTheBlankLineAfterIt() throws {
        let result = try memo(script).removingReferences(to: "case-01.png")
        #expect(text(result.memo) == "# case\n\n- one\n\n![case-00](case-00.png)\n\n- three\n\n![case-02](case-02.png)\n")
        #expect(result.kept == 0)
    }

    @Test func theLastBlockTakesTheBlankLineBeforeIt() throws {
        let result = try memo(script).removingReferences(to: "case-02.png")
        #expect(text(result.memo) == "# case\n\n- one\n\n![case-00](case-00.png)\n\n- two\n\n![case-01](case-01.png)\n")
    }

    @Test func crlfAndTheByteOrderMarkStay() throws {
        let crlf = "\u{FEFF}" + script.replacingOccurrences(of: "\n", with: "\r\n")
        let result = try memo(crlf).removingReferences(to: "case-00.png")
        #expect(text(result.memo) == "\u{FEFF}# case\r\n\r\n- two\r\n\r\n![case-01](case-01.png)\r\n\r\n- three\r\n\r\n![case-02](case-02.png)\r\n")
    }

    @Test func detailsUnderTheBulletGoToo() throws {
        let source = "# case\n\n- one\n  - detail\n\n![case-00](case-00.png)\n\n- two\n\n![case-01](case-01.png)\n"
        let result = try memo(source).removingReferences(to: "case-00.png")
        #expect(text(result.memo) == "# case\n\n- two\n\n![case-01](case-01.png)\n")
    }

    @Test func anImageWithoutABulletGoesAlone() throws {
        let source = "# case\n\nSome text.\n\n![case-00](case-00.png)\n\n- two\n\n![case-01](case-01.png)\n"
        let result = try memo(source).removingReferences(to: "case-00.png")
        #expect(text(result.memo) == "# case\n\nSome text.\n\n- two\n\n![case-01](case-01.png)\n")
    }

    @Test func anInlineReferenceIsKeptAndCounted() throws {
        let source = "# case\n\nSee ![case-00](case-00.png) here.\n\n- one\n\n![case-00](case-00.png)\n"
        let result = try memo(source).removingReferences(to: "case-00.png")
        #expect(text(result.memo) == "# case\n\nSee ![case-00](case-00.png) here.\n")
        #expect(result.kept == 1)
    }

    @Test func aFileTheMemoDoesNotReferenceChangesNothing() throws {
        let original = try memo(script)
        #expect(original.removingReferences(to: "other.png").memo == original)
    }
}

struct RemoveStepTests {
    @Test func restoringPutsTheEntryAfterTheOneItFollowed() {
        let sidecar = Sidecar(steps: ["a", "c"].map { SidecarStep(file: $0) })
        let removed = RemovedStep(
            file: "b",
            original: URL(fileURLWithPath: "/b"),
            inTrash: URL(fileURLWithPath: "/trash/b"),
            entry: SidecarStep(file: "b", excluded: true),
            after: "a",
            memoBefore: nil,
            memoAfter: nil
        )
        #expect(RemoveStep.restoring(removed, into: sidecar).steps.map(\.file) == ["a", "b", "c"])
        let first = RemovedStep(
            file: "b",
            original: removed.original,
            inTrash: removed.inTrash,
            entry: removed.entry,
            after: "gone",
            memoBefore: nil,
            memoAfter: nil
        )
        #expect(RemoveStep.restoring(first, into: sidecar).steps.map(\.file) == ["b", "a", "c"])
        let back = RemoveStep.restoring(removed, into: sidecar)
        #expect(RemoveStep.restoring(removed, into: back) == back)
    }
}

@MainActor
struct RemoveStepEditorTests {
    private let migrate = "poc-sample-vm-migrate"

    /// An editor on a copy of the fixture whose trash is a folder in `temp`.
    private func editor(_ temp: TempFolder) throws -> (editor: CaseEditor, trash: URL) {
        let folder = try temp.copy(fixture: migrate)
        let trash = temp.url.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let session = CaseSession(
            document: try CaseDocument.load(folder: folder),
            saveDelay: .seconds(60),
            watchDebounce: .milliseconds(50)
        )
        let editor = CaseEditor(session: session)
        editor.trash = { url in
            let target = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        return (editor, trash)
    }

    private func file(_ n: Int) -> String {
        "\(migrate)-0\(n).png"
    }

    @Test func ddTrashesTheCaptureAndTakesItOutOfSidecarAndMemo() throws {
        let temp = try TempFolder()
        let (editor, trash) = try editor(temp)
        let folder = editor.state.document.folder
        editor.perform(.add(Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))))
        editor.perform(.goTo(3))
        let item = Annotation(shape: .counter(at: CGPoint(x: 20, y: 20)))
        editor.perform(.add(item))
        editor.perform(.goTo(4))
        let later = Annotation(shape: .counter(at: CGPoint(x: 30, y: 30)))
        editor.perform(.add(later))
        #expect(editor.state.counterNumbers(items: editor.state.items)[later.id] == 3)
        var messages: [String] = []
        editor.onMessage = { messages.append($0) }

        editor.perform(.goTo(3))
        editor.perform(.removeStep)

        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent(file(2)).path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(file(2)).path))
        #expect(editor.state.document.steps.map(\.file) == [0, 1, 3, 4, 5].map(file))
        #expect(editor.state.currentStep?.file == file(3))
        #expect(editor.state.counterNumbers(items: editor.state.items)[later.id] == 2)
        let memo = try String(contentsOf: folder.appendingPathComponent("\(migrate).md"), encoding: .utf8)
        #expect(!memo.contains(file(2)))
        #expect(!memo.contains("Choose the target host"))
        #expect(memo.contains("- Open **Actions** > **Migrate** on the VM\n\n![\(migrate)-01](\(file(1)))\n\n- Confirm the migration"))
        let sidecar = try Sidecar.decode(Data(contentsOf: editor.state.document.sidecarURL))
        #expect(!sidecar.steps.contains { $0.file == file(2) })
        #expect(messages.last == "Moved \(file(2)) to the Trash; cmd-z puts it back")
        #expect(editor.state.undoLabel == "Remove Step")
        #expect(Dispatcher.isAvailable(.undo, in: editor.state))
    }

    @Test func cmdZPutsTheStepBackByteForByte() throws {
        let temp = try TempFolder()
        let (editor, _) = try editor(temp)
        let folder = editor.state.document.folder
        editor.perform(.goTo(3))
        editor.perform(.add(Annotation(shape: .counter(at: CGPoint(x: 20, y: 20)))))
        editor.close()
        let memoURL = folder.appendingPathComponent("\(migrate).md")
        let memoBefore = try Data(contentsOf: memoURL)
        let sidecarBefore = try Data(contentsOf: editor.state.document.sidecarURL)
        let capture = try Data(contentsOf: folder.appendingPathComponent(file(2)))

        editor.perform(.removeStep)
        editor.perform(.goTo(1))
        editor.perform(.undo)

        #expect(try Data(contentsOf: memoURL) == memoBefore)
        #expect(try Data(contentsOf: editor.state.document.sidecarURL) == sidecarBefore)
        #expect(try Data(contentsOf: folder.appendingPathComponent(file(2))) == capture)
        #expect(editor.state.currentStep?.file == file(2))
        #expect(editor.state.removed.isEmpty)
        #expect(editor.state.undoLabel == nil)
    }

    @Test func undoTakesBackNewerEditsBeforeTheRemoval() throws {
        let temp = try TempFolder()
        let (editor, _) = try editor(temp)
        editor.perform(.removeStep)
        let item = Annotation(shape: .counter(at: CGPoint(x: 20, y: 20)))
        editor.perform(.add(item))
        #expect(editor.state.undoLabel == "Add")

        editor.perform(.undo)
        #expect(editor.state.items.isEmpty)
        #expect(editor.state.document.steps.count == 5)
        #expect(editor.state.undoLabel == "Remove Step")

        editor.perform(.undo)
        #expect(editor.state.document.steps.count == 6)
        #expect(editor.state.currentStep?.file == file(0))
    }

    @Test func theLastStepCanBeRemovedAndPutBack() throws {
        let temp = try TempFolder()
        let (editor, _) = try editor(temp)
        for _ in 0..<6 {
            editor.perform(.removeStep)
        }
        #expect(editor.state.document.steps.isEmpty)
        #expect(editor.state.currentStep == nil)
        #expect(Dispatcher.isAvailable(.undo, in: editor.state))
        editor.perform(.undo)
        #expect(editor.state.document.steps.map(\.file) == [file(5)])
    }

    @Test func aMemoChangedSinceIsNotOverwritten() throws {
        let temp = try TempFolder()
        let (editor, _) = try editor(temp)
        var messages: [String] = []
        editor.onMessage = { messages.append($0) }
        editor.perform(.removeStep)
        let memoURL = editor.state.document.folder.appendingPathComponent("\(migrate).md")
        try (String(contentsOf: memoURL, encoding: .utf8) + "\nEdited elsewhere.\n").write(to: memoURL, atomically: true, encoding: .utf8)
        editor.session.reload()
        editor.perform(.undo)
        #expect(editor.state.document.steps.count == 6)
        #expect(editor.state.document.memo?.entry(for: file(0)) == nil)
        #expect(messages.last == "Put \(file(0)) back; the memo changed since, so its block was not put back")
    }

    @Test func aCapturePutBackByFinderStillGetsItsEntryBack() throws {
        let temp = try TempFolder()
        let (editor, trash) = try editor(temp)
        let folder = editor.state.document.folder
        editor.perform(.removeStep)
        try FileManager.default.moveItem(
            at: trash.appendingPathComponent(file(0)),
            to: folder.appendingPathComponent(file(0))
        )
        editor.perform(.undo)
        #expect(editor.state.document.steps.first?.file == file(0))
        #expect(editor.state.document.memo?.entry(for: file(0))?.caption == "Open the VM list and pick the running VM to migrate")
    }

    @Test func aCaptureGoneFromTheTrashIsSaidAndForgotten() throws {
        let temp = try TempFolder()
        let (editor, trash) = try editor(temp)
        var messages: [String] = []
        editor.onMessage = { messages.append($0) }
        editor.perform(.removeStep)
        try FileManager.default.removeItem(at: trash.appendingPathComponent(file(0)))
        editor.perform(.undo)
        #expect(messages.last == "\(file(0)) cannot be put back: it is no longer in the Trash")
        #expect(editor.state.removed.isEmpty)
        #expect(editor.state.document.steps.count == 5)
    }

    @Test func aFailedTrashChangesNothing() throws {
        let temp = try TempFolder()
        let (editor, _) = try editor(temp)
        struct Refused: Error {}
        editor.trash = { _ in throw Refused() }
        var messages: [String] = []
        editor.onMessage = { messages.append($0) }
        editor.perform(.removeStep)
        #expect(editor.state.document.steps.count == 6)
        #expect(editor.state.removed.isEmpty)
        #expect(messages.last?.hasPrefix("Not removed: ") == true)
    }

    @Test func aReadOnlyCaseRefuses() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        try Data("{ broken".utf8).write(to: folder.appendingPathComponent("\(migrate).snotate.json"))
        var state = EditorState(document: try CaseDocument.load(folder: folder))
        let effects = Dispatcher.apply(Invocation(.removeStep), to: &state)
        #expect(effects.count == 1)
        if case .message(let text) = effects.first {
            #expect(text.hasPrefix("Read-only"))
        } else {
            Issue.record("expected a refusal")
        }
    }
}
