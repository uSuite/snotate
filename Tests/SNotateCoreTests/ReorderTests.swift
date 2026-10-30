import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct ReorderTests {
    private func order(_ fixture: EditorFixture) -> [Int] {
        fixture.state.document.steps.map { Int($0.file.dropLast(4).suffix(2))! }
    }

    @Test func jAndKMoveTheCurrentStepAndKeepItCurrent() throws {
        var fixture = try EditorFixture()
        #expect(DefaultKeymap.keymap.command(for: [Key("J")]) == .moveStepLater)
        #expect(DefaultKeymap.keymap.command(for: [Key("K")]) == .moveStepEarlier)
        #expect(fixture.run(.moveStepLater) == [.sidecarChanged])
        #expect(order(fixture) == [1, 0, 2, 3, 4, 5])
        #expect(fixture.state.current == 1)
        fixture.run(.moveStepLater, count: 3)
        #expect(order(fixture) == [1, 2, 3, 4, 0, 5])
        #expect(fixture.run(.moveStepLater, count: 9) == [.sidecarChanged])
        #expect(order(fixture) == [1, 2, 3, 4, 5, 0])
        #expect(fixture.run(.moveStepLater).isEmpty)
        fixture.run(.moveStepEarlier, count: 5)
        #expect(order(fixture) == [0, 1, 2, 3, 4, 5])
        #expect(fixture.run(.moveStepEarlier).isEmpty)
    }

    @Test func aDragPlacesTheStepInAGapAndUndoes() throws {
        var fixture = try EditorFixture()
        fixture.run(.moveStep("poc-sample-vm-migrate-04.png", to: 1))
        #expect(order(fixture) == [0, 4, 1, 2, 3, 5])
        #expect(fixture.state.current == 1)
        fixture.run(.moveStep("poc-sample-vm-migrate-00.png", to: 6))
        #expect(order(fixture) == [4, 1, 2, 3, 5, 0])
        #expect(fixture.run(.moveStep("poc-sample-vm-migrate-02.png", to: 2)).isEmpty)
        #expect(fixture.run(.moveStep("poc-sample-vm-migrate-02.png", to: 3)).isEmpty)
        fixture.run(.undo)
        fixture.run(.undo)
        #expect(order(fixture) == [0, 1, 2, 3, 4, 5])
        #expect(fixture.state.undo.redoLabel == "Move Step")
    }

    @Test func countersFollowTheNewOrder() throws {
        let counter = Annotation(shape: .counter(at: CGPoint(x: 10, y: 10)))
        var fixture = try EditorFixture(items: [counter])
        fixture.state.document.sidecar.steps[2].items = [Annotation(shape: .counter(at: .zero))]
        let later = fixture.state.document.sidecar.steps[2].items[0].id
        #expect(fixture.state.document.counterNumbers[counter.id] == 1)
        fixture.run(.moveStepLater, count: 4)
        #expect(fixture.state.document.counterNumbers[later] == 1)
        #expect(fixture.state.document.counterNumbers[counter.id] == 2)
    }
}
