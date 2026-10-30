import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct HighlightToolTests {
    private func draw(
        from start: CGPoint,
        to end: CGPoint,
        shift: Bool = false,
        option: Bool = false,
        fixture: inout EditorFixture
    ) throws -> Shape? {
        if fixture.state.tool != .highlight {
            fixture.run(.tool(.highlight))
        }
        var gesture = try #require(Gesture.begin(at: start, in: fixture.state, shift: shift, tolerance: 4, handleRadius: 8).gesture)
        gesture.drag(to: end, shift: shift, option: option, in: fixture.state, snapThreshold: nil)
        let commands = gesture.finish(in: fixture.state, minimumLength: 4)
        guard commands.count == 1, case .add(let annotation) = commands[0] else {
            return nil
        }
        return annotation.shape
    }

    @Test func hPicksTheToolAndASecondPressSwitchesToSpotlight() throws {
        #expect(DefaultKeymap.keymap.command(for: [Key("h")]) == .tool(.highlight))
        var fixture = try EditorFixture()
        fixture.run(.tool(.highlight))
        #expect(fixture.run(.tool(.highlight)) == [.message("Highlight: spotlight")])
        #expect(fixture.run(.tool(.highlight)) == [.message("Highlight: marker")])
    }

    @Test func highlightsDrawLikeRectangles() throws {
        var fixture = try EditorFixture()
        #expect(try draw(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 100), fixture: &fixture)
            == .highlight(CGRect(x: 100, y: 100, width: 200, height: 100), spotlight: false))
        #expect(try draw(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 260, y: 230), shift: true, option: true, fixture: &fixture)
            == .highlight(CGRect(x: 140, y: 140, width: 120, height: 120), spotlight: false))
        #expect(try draw(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 103), fixture: &fixture) == nil)
        fixture.run(.tool(.highlight))
        #expect(try draw(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150), fixture: &fixture)
            == .highlight(CGRect(x: 100, y: 100, width: 100, height: 50), spotlight: true))
    }

    @Test func fSwitchesSelectedHighlightsBetweenMarkerAndSpotlight() throws {
        let marker = Annotation(shape: .highlight(CGRect(x: 0, y: 0, width: 50, height: 50), spotlight: false))
        let spot = Annotation(shape: .highlight(CGRect(x: 100, y: 0, width: 50, height: 50), spotlight: true))
        var fixture = try EditorFixture(items: [marker, spot])
        fixture.run(.select([spot.id]))
        fixture.run(.fill)
        #expect(fixture.items.map(\.shape.fill) == [false, false])
        fixture.run(.selectAll)
        fixture.run(.fill)
        #expect(fixture.items.map(\.shape.fill) == [true, true])
    }
}
