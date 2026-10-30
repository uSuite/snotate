import Foundation
import Testing
@testable import SNotateCore

struct UndoStackTests {
    private func snapshot(_ counter: String, step: String? = "a.png", selection: Set<UUID> = []) -> UndoStack.Snapshot {
        UndoStack.Snapshot(
            sidecar: Sidecar(counter: counter),
            step: step,
            selection: selection
        )
    }

    @Test func undoAndRedoWalkTheEntries() {
        var stack = UndoStack()
        #expect(stack.undoLabel == nil)
        stack.record("Add", before: snapshot("0"), after: snapshot("1"))
        stack.record("Move", before: snapshot("1"), after: snapshot("2"))
        #expect(stack.undoLabel == "Move")
        #expect(stack.undo() == snapshot("1"))
        #expect(stack.redoLabel == "Move")
        #expect(stack.undo() == snapshot("0"))
        #expect(stack.undo() == nil)
        #expect(stack.redo() == snapshot("1"))
        #expect(stack.redo() == snapshot("2"))
        #expect(stack.redo() == nil)
    }

    @Test func aNewEditClearsRedo() {
        var stack = UndoStack()
        stack.record("Add", before: snapshot("0"), after: snapshot("1"))
        _ = stack.undo()
        stack.record("Delete", before: snapshot("0"), after: snapshot("3"))
        #expect(stack.redoLabel == nil)
        #expect(stack.undo() == snapshot("0"))
    }

    @Test func textEditsOnOneAnnotationCoalesceUntilEnded() {
        let id = UUID()
        var stack = UndoStack()
        stack.record("Edit Text", before: snapshot("a"), after: snapshot("ab"), coalesce: id)
        stack.record("Edit Text", before: snapshot("ab"), after: snapshot("abc"), coalesce: id)
        #expect(stack.count == 1)
        stack.endCoalescing()
        stack.record("Edit Text", before: snapshot("abc"), after: snapshot("abcd"), coalesce: id)
        #expect(stack.count == 2)
        stack.record("Edit Text", before: snapshot("abcd"), after: snapshot("x"), coalesce: UUID())
        #expect(stack.count == 3)
        #expect(stack.undo() == snapshot("abcd"))
        #expect(stack.undo() == snapshot("abc"))
        #expect(stack.undo() == snapshot("a"))
    }

    @Test func otherEditsAndUndoEndCoalescing() {
        let id = UUID()
        var stack = UndoStack()
        stack.record("Edit Text", before: snapshot("a"), after: snapshot("ab"), coalesce: id)
        stack.record("Move", before: snapshot("ab"), after: snapshot("m"))
        stack.record("Edit Text", before: snapshot("m"), after: snapshot("mc"), coalesce: id)
        #expect(stack.count == 3)
        _ = stack.undo()
        stack.record("Edit Text", before: snapshot("m"), after: snapshot("md"), coalesce: id)
        #expect(stack.count == 3)
        #expect(stack.undo() == snapshot("m"))
    }

    @Test func clearEmptiesBothSides() {
        var stack = UndoStack()
        stack.record("Add", before: snapshot("0"), after: snapshot("1"))
        stack.record("Add", before: snapshot("1"), after: snapshot("2"))
        _ = stack.undo()
        stack.clear()
        #expect(stack.undoLabel == nil)
        #expect(stack.redoLabel == nil)
    }
}
