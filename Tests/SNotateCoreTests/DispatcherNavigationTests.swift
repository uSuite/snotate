import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

/// Shared setup for the dispatcher tests: the migrate fixture loaded from a
/// temp copy, with optional annotations on its first step.
struct EditorFixture {
    let temp: TempFolder
    var state: EditorState

    init(
        items: [Annotation] = [],
        fixture: String = "poc-sample-vm-migrate",
        sidecar: Data? = nil
    ) throws {
        temp = try TempFolder()
        let folder = try temp.copy(fixture: fixture)
        if let sidecar {
            try sidecar.write(to: folder.appendingPathComponent("\(fixture).snotate.json"))
        }
        var document = try CaseDocument.load(folder: folder)
        document.sidecar.steps[0].items = items
        state = EditorState(document: document)
    }

    @discardableResult
    mutating func run(_ command: Command, count: Int? = nil) -> [Effect] {
        Dispatcher.apply(Invocation(command, count: count), to: &state)
    }

    var items: [Annotation] {
        state.document.sidecar.steps[state.sidecarIndex!].items
    }
}

struct DispatcherNavigationTests {
    @Test func startsAtTheFirstStepOrTheOneAsked() throws {
        var fixture = try EditorFixture()
        #expect(fixture.state.current == 0)
        #expect(fixture.state.currentStep?.file == "poc-sample-vm-migrate-00.png")
        fixture.state = EditorState(document: fixture.state.document, file: "poc-sample-vm-migrate-03.png")
        #expect(fixture.state.current == 3)
    }

    @Test func movesWithCountsStopAtTheEnds() throws {
        var fixture = try EditorFixture()
        fixture.run(.next)
        #expect(fixture.state.current == 1)
        fixture.run(.next, count: 3)
        #expect(fixture.state.current == 4)
        fixture.run(.next, count: 9)
        #expect(fixture.state.current == 5)
        fixture.run(.previous, count: 2)
        #expect(fixture.state.current == 3)
        fixture.run(.first)
        #expect(fixture.state.current == 0)
        fixture.run(.previous)
        #expect(fixture.state.current == 0)
        fixture.run(.last)
        #expect(fixture.state.current == 5)
        fixture.run(.goTo(2))
        #expect(fixture.state.current == 1)
        fixture.run(.goTo(99))
        #expect(fixture.state.current == 5)
    }

    @Test func movingClearsTheSelectionAndIsNotUndoable() throws {
        let item = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))
        var fixture = try EditorFixture(items: [item])
        fixture.run(.selectAll)
        #expect(fixture.state.selection == [item.id])
        #expect(fixture.run(.next).isEmpty)
        #expect(fixture.state.selection.isEmpty)
        #expect(fixture.state.undo.count == 0)
    }

    @Test func selectionOnlyHoldsItemsOfTheCurrentStep() throws {
        let a = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))
        let b = Annotation(shape: .counter(at: CGPoint(x: 50, y: 10)))
        var fixture = try EditorFixture(items: [a, b])
        fixture.run(.select([a.id, UUID()]))
        #expect(fixture.state.selection == [a.id])
        fixture.run(.toggleSelect(b.id))
        #expect(fixture.state.selection == [a.id, b.id])
        fixture.run(.toggleSelect(a.id))
        #expect(fixture.state.selection == [b.id])
        fixture.run(.toggleSelect(UUID()))
        #expect(fixture.state.selection == [b.id])
        fixture.run(.deselect)
        #expect(fixture.state.selection.isEmpty)
        fixture.run(.selectAll)
        #expect(fixture.state.selection == [a.id, b.id])
    }

    @Test func aCaseWithoutImagesHasNoCurrentStep() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("poc-empty-case-here")
        var state = EditorState(document: try CaseDocument.load(folder: folder))
        #expect(state.current == nil)
        #expect(Dispatcher.apply(Invocation(.next), to: &state).isEmpty)
        #expect(Dispatcher.apply(Invocation(.delete), to: &state).isEmpty)
    }
}

struct CaseNavigationTests {
    @Test func caseKeysAskTheWindowForASiblingAndChangeNothing() throws {
        var fixture = try EditorFixture()
        let sidecar = fixture.state.document.sidecar
        #expect(fixture.run(.caseNext) == [.siblingCase(1)])
        #expect(fixture.run(.casePrevious, count: 2) == [.siblingCase(-2)])
        #expect(fixture.run(.commandLine) == [.commandLine])
        #expect(fixture.state.document.sidecar == sidecar)
        #expect(fixture.state.current == 0)
    }

    @Test func theyWorkInACaseWithoutImages() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("poc-demo-vm-empty")
        var state = EditorState(document: try CaseDocument.load(folder: folder))
        #expect(state.current == nil)
        #expect(Dispatcher.apply(Invocation(.caseNext), to: &state) == [.siblingCase(1)])
        #expect(Dispatcher.apply(Invocation(.commandLine), to: &state) == [.commandLine])
    }

    @Test func theCommandLineTakesAStepNumberOrACommand() throws {
        #expect(try Command.parseCommandLine("4") == .goTo(4))
        #expect(try Command.parseCommandLine("  12 ") == .goTo(12))
        #expect(try Command.parseCommandLine("zoom-fit") == .zoomFit)
        #expect(try Command.parseCommandLine("tool arrow") == .tool(.arrow))
        #expect(try Command.parseCommandLine("case-next") == .caseNext)
        #expect(throws: CommandError.badArgument("no step 0; steps start at 1")) {
            try Command.parseCommandLine("0")
        }
        #expect(throws: CommandError.unknown("fly")) {
            try Command.parseCommandLine("fly")
        }
        #expect(throws: CommandError.unknown("")) {
            try Command.parseCommandLine("  ")
        }
    }
}
