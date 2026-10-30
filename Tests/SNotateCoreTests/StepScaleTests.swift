import Foundation
import Testing
@testable import SNotateCore

struct StepScaleTests {
    private let base = PixelSize(width: 1600, height: 1000)

    @Test func pixelSizeComesFromTheHeader() {
        let scale = Fixtures.url("poc-sample-vm-scale")
        #expect(PixelSize(imageAt: scale.appendingPathComponent("poc-sample-vm-scale-00.png")) == PixelSize(width: 1600, height: 1000))
        #expect(PixelSize(imageAt: scale.appendingPathComponent("poc-sample-vm-scale-01.png")) == PixelSize(width: 3200, height: 2000))
        #expect(PixelSize(imageAt: scale.appendingPathComponent("poc-sample-vm-scale-02.png")) == PixelSize(width: 1592, height: 982))
        #expect(PixelSize(imageAt: scale.appendingPathComponent("poc-sample-vm-scale.md")) == nil)
        #expect(PixelSize(imageAt: scale.appendingPathComponent("missing.png")) == nil)
    }

    @Test func equalSizesMatch() {
        #expect(StepScale(recorded: base, actual: base) == .match)
    }

    @Test func exactMultiplesScaleInEitherDirection() {
        #expect(StepScale(recorded: base, actual: PixelSize(width: 3200, height: 2000)) == .scaled(2))
        #expect(StepScale(recorded: PixelSize(width: 3036, height: 1784), actual: PixelSize(width: 1518, height: 892)) == .scaled(0.5))
        #expect(StepScale(recorded: base, actual: PixelSize(width: 4800, height: 3000)) == .scaled(3))
    }

    @Test func anythingElseIsFlagged() {
        let odd = PixelSize(width: 1592, height: 982)
        #expect(StepScale(recorded: base, actual: odd) == .mismatch(recorded: base, actual: odd))
        // Each side a multiple, but not by the same factor.
        let stretched = PixelSize(width: 3200, height: 3000)
        #expect(StepScale(recorded: base, actual: stretched) == .mismatch(recorded: base, actual: stretched))
        let shrunk = PixelSize(width: 800, height: 1000)
        #expect(StepScale(recorded: base, actual: shrunk) == .mismatch(recorded: base, actual: shrunk))
    }
}
