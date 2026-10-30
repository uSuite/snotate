import Foundation
import Testing
@testable import SNotateCore

@MainActor
struct CaseSessionTests {
    private let migrate = "poc-sample-vm-migrate"

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func session(
        _ temp: TempFolder,
        saveDelay: Duration = .milliseconds(50)
    ) throws -> CaseSession {
        let folder = try temp.copy(fixture: migrate)
        return CaseSession(
            document: try CaseDocument.load(folder: folder),
            saveDelay: saveDelay,
            watchDebounce: .milliseconds(50)
        )
    }

    private func onDisk(_ session: CaseSession) -> Data? {
        try? Data(contentsOf: session.document.sidecarURL)
    }

    @Test func openingAndWaitingWritesNothing() async throws {
        let temp = try TempFolder()
        let session = try session(temp)
        try await Task.sleep(for: .milliseconds(200))
        session.flush()
        #expect(onDisk(session) == nil)
    }

    @Test func aBurstOfChangesIsOneDebouncedSave() async throws {
        let temp = try TempFolder()
        let session = try session(temp)
        #expect(session.change { $0.steps[1].excluded = true })
        #expect(session.change { $0.steps[2].caption = "draft" })
        #expect(onDisk(session) == nil)
        await waitUntil { onDisk(session) != nil }
        #expect(onDisk(session) == session.document.sidecar.encoded())
        let saved = try Sidecar.decode(onDisk(session)!)
        #expect(saved.steps.count == 6)
        #expect(saved.steps[1].excluded)
        #expect(saved.steps[2].caption == "draft")
        #expect(saved.steps.allSatisfy { $0.size == PixelSize(width: 1600, height: 1000) })
    }

    @Test func flushSavesAtOnceAndANoOpChangeIsNotSaved() throws {
        let temp = try TempFolder()
        let session = try session(temp, saveDelay: .seconds(60))
        #expect(session.change { _ in })
        session.flush()
        #expect(onDisk(session) == nil)
        session.change { $0.counter = "restart" }
        session.flush()
        #expect(try Sidecar.decode(onDisk(session)!).counter == "restart")
    }

    @Test func ownSavesDoNotCountAsOutsideChanges() async throws {
        let temp = try TempFolder()
        let session = try session(temp)
        var reloads = 0
        session.onReload = { reloads += 1 }
        session.change { $0.steps[0].excluded = true }
        session.flush()
        try await Task.sleep(for: .milliseconds(300))
        #expect(reloads == 0)
        #expect(session.document.sidecar.steps[0].excluded)
    }

    @Test func anOutsideEditIsReloaded() async throws {
        let temp = try TempFolder()
        let session = try session(temp)
        var reloads = 0
        session.onReload = { reloads += 1 }
        try await Task.sleep(for: .milliseconds(100))
        var edited = session.document.sidecar
        edited.steps.reverse()
        try edited.encoded().write(to: session.document.sidecarURL, options: .atomic)
        await waitUntil { reloads > 0 }
        #expect(session.document.steps.first?.file == "\(migrate)-05.png")
        #expect(reloads == 1)
    }

    @Test func aNewImageAppearsAsAStep() async throws {
        let temp = try TempFolder()
        let session = try session(temp)
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.copyItem(
            at: session.document.steps[0].url,
            to: session.document.folder.appendingPathComponent("\(migrate)-06.png")
        )
        await waitUntil { session.document.steps.count == 7 }
        #expect(session.document.steps.last?.file == "\(migrate)-06.png")
    }

    @Test func anInPlaceMemoEditIsReloaded() async throws {
        let temp = try TempFolder()
        let session = try session(temp)
        var reloads = 0
        session.onReload = { reloads += 1 }
        try await Task.sleep(for: .milliseconds(100))
        let handle = try FileHandle(forWritingTo: session.document.memoURL!)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n- Extra step\n\n![extra](extra.png)\n".utf8))
        try handle.close()
        await waitUntil { reloads > 0 }
        #expect(session.document.memo?.entry(for: "extra.png")?.caption == "Extra step")
    }

    @Test func anOutsideEditWinsOverAPendingChange() async throws {
        let temp = try TempFolder()
        let session = try session(temp, saveDelay: .seconds(60))
        try await Task.sleep(for: .milliseconds(100))
        session.change { $0.steps[0].excluded = true }
        let outside = Sidecar(counter: "restart", steps: [SidecarStep(file: "\(migrate)-02.png")])
        try outside.encoded().write(to: session.document.sidecarURL, options: .atomic)
        await waitUntil { session.droppedLocalChange }
        #expect(session.document.sidecar.counter == "restart")
        // The outside file lists only step 02; the others come back as new.
        #expect(session.document.added.count == 5)
        #expect(!session.document.sidecar.steps.contains { $0.excluded })
        session.flush()
        #expect(onDisk(session) == outside.encoded())
    }

    @Test func anUnreadableSidecarMakesTheCaseReadOnlyUntilItParses() async throws {
        let temp = try TempFolder()
        let folder = try temp.copy(fixture: migrate)
        let url = folder.appendingPathComponent("\(migrate).snotate.json")
        let conflict = Data("<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> other\n".utf8)
        try conflict.write(to: url)
        let session = CaseSession(
            document: try CaseDocument.load(folder: folder),
            saveDelay: .milliseconds(10),
            watchDebounce: .milliseconds(50)
        )
        #expect(session.isReadOnly)
        #expect(!session.change { $0.steps[0].excluded = true })
        session.flush()
        #expect(try Data(contentsOf: url) == conflict)
        try Sidecar(steps: [SidecarStep(file: "\(migrate)-00.png")]).encoded().write(to: url, options: .atomic)
        await waitUntil { !session.isReadOnly }
        #expect(session.change { $0.steps[0].excluded = true })
        session.flush()
        #expect(try Sidecar.decode(Data(contentsOf: url)).steps[0].excluded)
    }
}
