import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct StoryboardModeTests {
    private let box = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 100), fill: true))

    @Test func theStoryboardShowsAndEnterOpensTheSelectedStep() throws {
        var fixture = try EditorFixture(items: [box])
        fixture.run(.select([box.id]))
        fixture.run(.viewStoryboard)
        #expect(fixture.state.mode == .storyboard)
        #expect(fixture.state.selection.isEmpty)
        fixture.run(.next)
        fixture.run(.next)
        #expect(fixture.state.current == 2)
        fixture.run(.edit)
        #expect(fixture.state.mode == .step)
        #expect(fixture.state.current == 2)
    }

    @Test func escGoesBackToTheStoryboardAfterTheToolAndSelection() throws {
        var fixture = try EditorFixture(items: [box])
        fixture.run(.viewStoryboard)
        fixture.run(.edit)
        fixture.run(.tool(.arrow))
        fixture.run(.select([box.id]))
        fixture.run(.tool(.select))
        #expect(fixture.state.mode == .step)
        fixture.run(.tool(.select))
        #expect(fixture.state.selection.isEmpty)
        #expect(fixture.state.mode == .step)
        fixture.run(.tool(.select))
        #expect(fixture.state.mode == .storyboard)
        fixture.run(.viewStep)
        fixture.run(.tool(.select))
        #expect(fixture.state.mode == .step)
    }

    @Test func inTheStoryboardArrowsMoveFramesAndToolKeysDoNothing() throws {
        var fixture = try EditorFixture()
        fixture.run(.viewStoryboard)
        #expect(fixture.run(.nudge(.down, big: false)) == [.storyboardMove(.down)])
        #expect(fixture.run(.nudge(.right, big: true), count: 2) == [.storyboardMove(.right), .storyboardMove(.right)])
        #expect(fixture.run(.tool(.arrow)).isEmpty)
        #expect(fixture.state.tool == .select)
        #expect(fixture.run(.zoomIn) == [.zoom(.steps(1))])
        #expect(fixture.run(.editCaption) == [.beginCaptionEdit])
    }

    @Test func iInTheSingleViewEditsTheCaptionInTheStoryboard() throws {
        var fixture = try EditorFixture()
        fixture.run(.next)
        #expect(fixture.run(.editCaption) == [.beginCaptionEdit])
        #expect(fixture.state.mode == .storyboard)
        #expect(fixture.state.current == 1)
    }

    @Test func theKeysAreBound() throws {
        let keymap = DefaultKeymap.keymap
        #expect(keymap.command(for: try Key.parseSequence("cmd-1")) == .viewStep)
        #expect(keymap.command(for: try Key.parseSequence("cmd-2")) == .viewStoryboard)
        #expect(keymap.command(for: try Key.parseSequence("i")) == .editCaption)
    }
}
