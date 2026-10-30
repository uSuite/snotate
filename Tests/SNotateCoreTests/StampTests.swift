import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct StampTests {
    private let blur = Annotation(shape: .blur(CGRect(x: 300, y: 12, width: 150, height: 40), pixelate: false))
    private let spot = Annotation(shape: .highlight(CGRect(x: 100, y: 100, width: 50, height: 50), spotlight: true), preset: 2)
    private let arrow = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 10, y: 10), curve: nil))

    private func items(_ fixture: EditorFixture, _ n: Int) -> [Annotation] {
        fixture.state.document.sidecar.steps[n].items
    }

    @Test func followingCopiesTheRegionsOnceAndUndoesAsOne() throws {
        var fixture = try EditorFixture(items: [blur, spot, arrow])
        fixture.run(.selectAll)
        #expect(fixture.run(.stamp(.following)) == [.sidecarChanged, .message("Stamped 2 regions onto 5 steps")])
        for n in 1...5 {
            #expect(items(fixture, n).map(\.shape) == [blur.shape, spot.shape])
            #expect(items(fixture, n).map(\.preset) == [1, 2])
        }
        #expect(Set(items(fixture, 1).map(\.id)).isDisjoint(with: [blur.id, spot.id]))
        #expect(fixture.run(.stamp(.following)) == [.message("Nothing new to stamp")])
        #expect(fixture.state.undo.undoLabel == "Stamp")
        fixture.run(.undo)
        #expect((1...5).allSatisfy { items(fixture, $0).isEmpty })
        #expect(fixture.state.current == 0)
        #expect(fixture.state.selection == [blur.id, spot.id, arrow.id])
    }

    @Test func previousNextAndAllPickTheirSteps() throws {
        var fixture = try EditorFixture()
        fixture.run(.next)
        fixture.run(.next)
        fixture.run(.add(blur))
        fixture.run(.select([blur.id]))
        fixture.run(.stamp(.previous))
        #expect(items(fixture, 1).count == 1)
        #expect(items(fixture, 0).isEmpty)
        fixture.run(.stamp(.next))
        #expect(items(fixture, 3).count == 1)
        #expect(items(fixture, 4).isEmpty)
        fixture.run(.stamp(.all))
        #expect((0...5).allSatisfy { items(fixture, $0).count == 1 })
    }

    @Test func excludedAndOtherSizedStepsAreSkipped() throws {
        var fixture = try EditorFixture(items: [blur])
        fixture.state.document.sidecar.steps[2].excluded = true
        fixture.state.document.sidecar.steps[3].size = PixelSize(width: 800, height: 500)
        fixture.run(.select([blur.id]))
        #expect(fixture.run(.stamp(.following)) == [.sidecarChanged, .message("Stamped 1 region onto 3 steps (2 skipped: excluded or another size)")])
        #expect(items(fixture, 2).isEmpty)
        #expect(items(fixture, 3).isEmpty)
    }

    @Test func onlyRegionsAreStampedAndTheCropWhileCropping() throws {
        var fixture = try EditorFixture(items: [arrow])
        fixture.run(.select([arrow.id]))
        #expect(fixture.run(.stamp(.following)) == [.message("Select a blur or highlight region to stamp")])
        fixture.run(.tool(.crop))
        #expect(fixture.run(.stamp(.following)) == [.message("This step has no crop to stamp")])
        let crop = CGRect(x: 10, y: 10, width: 800, height: 500)
        fixture.run(.setCrop(crop))
        #expect(fixture.run(.stamp(.following)) == [.sidecarChanged, .message("Stamped the crop onto 5 steps")])
        #expect((1...5).allSatisfy { fixture.state.document.sidecar.steps[$0].crop == crop })
        #expect((1...5).allSatisfy { items(fixture, $0).isEmpty })
    }

    @Test func theKeysAreBound() throws {
        #expect(DefaultKeymap.keymap.command(for: [Key(">")]) == .stamp(.following))
        #expect(DefaultKeymap.keymap.command(for: [Key("<")]) == .stamp(.previous))
        #expect(try Command.parseCommandLine("stamp-all") == .stamp(.all))
        #expect(try Command.parseCommandLine("stamp-next") == .stamp(.next))
    }
}
