import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct BlurToolTests {
    private func draw(
        from start: CGPoint,
        to end: CGPoint,
        fixture: inout EditorFixture
    ) throws -> Shape? {
        if fixture.state.tool != .blur {
            fixture.run(.tool(.blur))
        }
        var gesture = try #require(Gesture.begin(at: start, in: fixture.state, shift: false, tolerance: 4, handleRadius: 8).gesture)
        gesture.drag(to: end, shift: false, in: fixture.state, snapThreshold: nil)
        let commands = gesture.finish(in: fixture.state, minimumLength: 4)
        guard commands.count == 1, case .add(let annotation) = commands[0] else {
            return nil
        }
        return annotation.shape
    }

    @Test func bPicksTheToolAndASecondPressSwitchesToPixelate() throws {
        #expect(DefaultKeymap.keymap.command(for: [Key("b")]) == .tool(.blur))
        #expect(Tool.allCases.filter(\.fills) == [.rectangle, .ellipse, .text, .highlight, .blur])
        var fixture = try EditorFixture()
        fixture.run(.tool(.blur))
        #expect(fixture.run(.tool(.blur)) == [.message("Blur: pixelate")])
        #expect(fixture.run(.tool(.blur)) == [.message("Blur: blur")])
    }

    @Test func regionsDrawLikeRectanglesInTheCurrentVariant() throws {
        var fixture = try EditorFixture()
        #expect(try draw(from: CGPoint(x: 450, y: 52), to: CGPoint(x: 300, y: 12), fixture: &fixture)
            == .blur(CGRect(x: 300, y: 12, width: 150, height: 40), pixelate: false))
        #expect(try draw(from: CGPoint(x: 300, y: 12), to: CGPoint(x: 450, y: 14), fixture: &fixture) == nil)
        fixture.run(.tool(.blur))
        #expect(try draw(from: CGPoint(x: 380, y: 230), to: CGPoint(x: 920, y: 360), fixture: &fixture)
            == .blur(CGRect(x: 380, y: 230, width: 540, height: 130), pixelate: true))
    }

    @Test func fSwitchesSelectedRegionsAndAClickInsideSelects() throws {
        let region = Annotation(shape: .blur(CGRect(x: 300, y: 12, width: 150, height: 40), pixelate: false))
        var fixture = try EditorFixture(items: [region])
        let (gesture, commands) = Gesture.begin(at: CGPoint(x: 375, y: 30), in: fixture.state, shift: false, tolerance: 4, handleRadius: 8)
        #expect(gesture != nil)
        #expect(commands == [.select([region.id])])
        fixture.run(.select([region.id]))
        fixture.run(.fill)
        #expect(fixture.items[0].shape == .blur(CGRect(x: 300, y: 12, width: 150, height: 40), pixelate: true))
    }
}
