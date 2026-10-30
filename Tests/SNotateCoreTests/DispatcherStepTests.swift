import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct DispatcherStepTests {
    private var step: SidecarStep {
        get throws {
            try #require(fixture.state.document.sidecar.steps.first)
        }
    }

    private var fixture: EditorFixture

    init() throws {
        fixture = try EditorFixture()
    }

    @Test mutating func cropIsClampedToTheImageAndCanBeRemoved() throws {
        #expect(fixture.run(.setCrop(CGRect(x: -20, y: 64, width: 1700, height: 900))) == [.sidecarChanged])
        #expect(try step.crop == CGRect(x: 0, y: 64, width: 1600, height: 900))
        #expect(fixture.state.undo.undoLabel == "Crop")
        #expect(fixture.run(.setCrop(CGRect(x: 2000, y: 0, width: 10, height: 10))) == [.message("The crop is outside the image.")])
        #expect(try step.crop == CGRect(x: 0, y: 64, width: 1600, height: 900))
        fixture.run(.setCrop(nil))
        #expect(try step.crop == nil)
        #expect(fixture.state.undo.undoLabel == "Remove Crop")
        fixture.run(.undo)
        #expect(try step.crop == CGRect(x: 0, y: 64, width: 1600, height: 900))
    }

    @Test mutating func excludeAndRestartCounterToggleAndStayNavigable() throws {
        fixture.run(.exclude)
        #expect(try step.excluded)
        #expect(fixture.state.currentStep?.excluded == true)
        #expect(fixture.state.undo.undoLabel == "Exclude Step")
        fixture.run(.next)
        fixture.run(.previous)
        #expect(fixture.state.current == 0)
        fixture.run(.exclude)
        #expect(try !step.excluded)
        #expect(fixture.state.undo.undoLabel == "Include Step")
        fixture.run(.restartCounter)
        #expect(try step.restartCounter)
        fixture.run(.undo)
        #expect(try !step.restartCounter)
    }

    @Test func aReadOnlyCaseRefusesEditsButStillNavigates() throws {
        let item = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))
        var fixture = try EditorFixture(
            items: [item],
            sidecar: Data("<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> other\n".utf8)
        )
        let before = fixture.state.document.sidecar
        for command: Command in [.add(item), .exclude, .restartCounter, .setCrop(nil), .undo, .redo] {
            let effects = fixture.run(command)
            #expect(effects.count == 1)
            guard case .message(let text) = effects.first else {
                Issue.record("expected a message for \(command)")
                continue
            }
            #expect(text.hasPrefix("Read-only"))
        }
        #expect(fixture.state.document.sidecar == before)
        #expect(fixture.state.undo.count == 0)
        fixture.run(.selectAll)
        #expect(fixture.state.selection == [item.id])
        fixture.run(.next)
        #expect(fixture.state.current == 1)
    }
}
