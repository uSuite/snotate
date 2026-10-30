import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

@MainActor
struct CaseEditorTests {
    private let migrate = "poc-sample-vm-migrate"
    private let item = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func editor(
        _ temp: TempFolder,
        saveDelay: Duration = .milliseconds(50),
        sidecar: Data? = nil
    ) throws -> CaseEditor {
        let folder = try temp.copy(fixture: migrate)
        if let sidecar {
            try sidecar.write(to: folder.appendingPathComponent("\(migrate).snotate.json"))
        }
        let session = CaseSession(
            document: try CaseDocument.load(folder: folder),
            saveDelay: saveDelay,
            watchDebounce: .milliseconds(50)
        )
        return CaseEditor(session: session)
    }

    private func onDisk(_ editor: CaseEditor) -> Sidecar? {
        (try? Data(contentsOf: editor.session.document.sidecarURL)).flatMap { try? Sidecar.decode($0) }
    }

    @Test func editsReachTheDiskThroughAutosave() async throws {
        let temp = try TempFolder()
        let editor = try editor(temp)
        var changes = 0
        editor.onChange = { changes += 1 }
        editor.perform(.add(item))
        #expect(changes == 1)
        #expect(editor.session.document.sidecar == editor.state.document.sidecar)
        await waitUntil { onDisk(editor) != nil }
        #expect(onDisk(editor)?.steps[0].items == [item])
    }

    @Test func closeSavesAWaitingChange() throws {
        let temp = try TempFolder()
        let editor = try editor(temp, saveDelay: .seconds(60))
        editor.perform(.add(item))
        #expect(onDisk(editor) == nil)
        editor.close()
        #expect(onDisk(editor)?.steps[0].items == [item])
    }

    @Test func anOutsideEditClearsUndoAndKeepsTheStepByFile() async throws {
        let temp = try TempFolder()
        let editor = try editor(temp)
        editor.perform(.add(item))
        editor.close()
        editor.perform(.goTo(4))
        #expect(editor.state.currentStep?.file == "\(migrate)-03.png")
        #expect(editor.state.undo.count == 1)
        try await Task.sleep(for: .milliseconds(150))
        var outside = editor.state.document.sidecar
        outside.steps.reverse()
        try outside.encoded().write(to: editor.session.document.sidecarURL, options: .atomic)
        await waitUntil { editor.state.undo.count == 0 }
        #expect(editor.state.document.steps.first?.file == "\(migrate)-05.png")
        #expect(editor.state.currentStep?.file == "\(migrate)-03.png")
        #expect(editor.state.selection.isEmpty)
        #expect(editor.perform(.undo).isEmpty)
    }

    @Test func refusalsAndDroppedChangesAreReported() async throws {
        let temp = try TempFolder()
        let readOnly = try editor(temp, sidecar: Data("<<<<<<< HEAD\n".utf8))
        var messages: [String] = []
        readOnly.onMessage = { messages.append($0) }
        readOnly.perform(.add(item))
        #expect(messages.count == 1)
        #expect(messages.first?.hasPrefix("Read-only") == true)

        let other = try TempFolder()
        let editor = try editor(other, saveDelay: .seconds(60))
        editor.onMessage = { messages.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        editor.perform(.add(item))
        try Sidecar(counter: "step").encoded().write(to: editor.session.document.sidecarURL, options: .atomic)
        await waitUntil { messages.count == 2 }
        #expect(messages.last == "Reloaded from disk; the last change was not saved.")
        #expect(editor.state.document.sidecar.counter == "step")
        #expect(editor.state.items.isEmpty)
    }
}

@MainActor
struct OwnSaveTests {
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Mouse positions are fractional and the sidecar keeps two decimals;
    /// reading back our own save must not look like an outside change,
    /// which would clear the selection and undo.
    @Test func fractionalEditsSurviveTheirOwnSave() async throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        let editor = CaseEditor(session: CaseSession(
            document: try CaseDocument.load(folder: folder),
            saveDelay: .milliseconds(20),
            watchDebounce: .milliseconds(50)
        ))
        var reloads = 0
        editor.session.onReload = { reloads += 1 }
        let item = Annotation(shape: .counter(at: CGPoint(x: 999.999_999_8, y: 560.004_9)))
        editor.perform(.add(item))
        #expect(editor.state.items.first?.shape == .counter(at: CGPoint(x: 1000, y: 560)))
        await waitUntil { FileManager.default.fileExists(atPath: editor.session.document.sidecarURL.path) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(reloads == 0)
        #expect(editor.state.selection == [item.id])
        #expect(editor.state.undo.count == 1)
    }

    @Test func everyEditStoresTwoDecimals() throws {
        var fixture = try EditorFixture()
        fixture.run(.add(Annotation(shape: .text(at: CGPoint(x: 1.234_5, y: 2.005), text: "x", pill: false, leader: CGPoint(x: 3.333_3, y: 4)))))
        fixture.run(.setCrop(CGRect(x: 10.111, y: 20.119, width: 300.501, height: 200)))
        #expect(fixture.items[0].shape == .text(at: CGPoint(x: 1.23, y: 2.01), text: "x", pill: false, leader: CGPoint(x: 3.33, y: 4)))
        #expect(fixture.state.document.sidecar.steps[0].crop == CGRect(x: 10.11, y: 20.12, width: 300.5, height: 200))
        let id = fixture.items[0].id
        fixture.run(.select([id]))
        fixture.run(.move([id], by: CGVector(dx: 0.333, dy: 0)))
        #expect(fixture.items[0].shape == .text(at: CGPoint(x: 1.56, y: 2.01), text: "x", pill: false, leader: CGPoint(x: 3.66, y: 4)))
    }

    @Test func aSiblingCaseTakesTheWindowsToolAndPresetButNotTheSelection() throws {
        let temp = try TempFolder()
        let migrate = try temp.copy(fixture: "poc-sample-vm-migrate")
        let first = CaseEditor(session: CaseSession(document: try CaseDocument.load(folder: migrate)))
        first.perform(.tool(.rectangle))
        first.perform(.tool(.rectangle))
        first.perform(.preset(3))
        let folder = try temp.copy(fixture: "poc-sample-vm-scale")
        let second = CaseEditor(session: CaseSession(document: try CaseDocument.load(folder: folder)))
        var changed = false
        second.onChange = { changed = true }
        second.adopt(from: first.state)
        #expect(second.state.tool == .rectangle)
        #expect(second.state.filled == [.rectangle])
        #expect(second.state.activePreset == 3)
        #expect(second.state.selection.isEmpty)
        #expect(second.state.undo.count == 0)
        #expect(changed)
    }

    @Test func newStylesRedrawAndKeepTheUndo() throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        let editor = CaseEditor(session: CaseSession(document: try CaseDocument.load(folder: folder)))
        editor.perform(.add(Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))))
        var changes = 0
        editor.onChange = { changes += 1 }
        var styles = Styles.builtIn
        styles.presets[4] = Styles.builtIn.presets[2]
        editor.setStyles(styles)
        editor.setStyles(styles)
        #expect(editor.state.styles == styles)
        #expect(changes == 1)
        #expect(editor.state.undo.count == 1)
    }
}

@MainActor
struct ReloadKeepsTheWindowTests {
    @Test func aReloadFromDiskKeepsTheViewAndTool() async throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: "poc-sample-vm-migrate")
        let editor = CaseEditor(session: CaseSession(
            document: try CaseDocument.load(folder: folder),
            saveDelay: .milliseconds(10),
            watchDebounce: .milliseconds(50)
        ))
        editor.perform(.tool(.blur))
        editor.perform(.tool(.blur))
        editor.perform(.viewStoryboard)
        let memo = folder.appendingPathComponent("poc-sample-vm-migrate.md")
        try Data((try String(contentsOf: memo, encoding: .utf8) + "\nEdited elsewhere.\n").utf8).write(to: memo)
        editor.session.reload()
        #expect(editor.state.caption(for: "poc-sample-vm-migrate-05.png") == "The VM is Running on the target host")
        #expect(editor.state.document.memo?.lines.last?.text == "Edited elsewhere.")
        #expect(editor.state.mode == .storyboard)
        #expect(editor.state.tool == .blur)
        #expect(editor.state.filled == [.blur])
    }
}
