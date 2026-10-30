import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct CounterNumberingTests {
    private func counter() -> Annotation {
        Annotation(shape: .counter(at: .zero))
    }

    private let arrow = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 1, y: 1), curve: nil))

    @Test func countersContinueAcrossStepsInDrawingOrder() {
        let (a, b, c) = (counter(), counter(), counter())
        let sidecar = Sidecar(steps: [
            SidecarStep(file: "00.png", items: [a, arrow, b]),
            SidecarStep(file: "01.png"),
            SidecarStep(file: "02.png", items: [c]),
        ])
        let numbers = CounterNumbering.numbers(in: sidecar, present: ["00.png", "01.png", "02.png"])
        #expect(numbers == [a.id: 1, b.id: 2, c.id: 3])
    }

    @Test func excludedAndMissingStepsUseNoNumbers() {
        let (a, b, c, d) = (counter(), counter(), counter(), counter())
        let sidecar = Sidecar(steps: [
            SidecarStep(file: "00.png", items: [a]),
            SidecarStep(file: "01.png", excluded: true, items: [b]),
            SidecarStep(file: "gone.png", items: [c]),
            SidecarStep(file: "03.png", items: [d]),
        ])
        let numbers = CounterNumbering.numbers(in: sidecar, present: ["00.png", "01.png", "03.png"])
        #expect(numbers == [a.id: 1, d.id: 2])
    }

    @Test func restartsPerStepOrWhereAsked() {
        let (a, b, c, d) = (counter(), counter(), counter(), counter())
        var sidecar = Sidecar(steps: [
            SidecarStep(file: "00.png", items: [a, b]),
            SidecarStep(file: "01.png", restartCounter: true, items: [c]),
            SidecarStep(file: "02.png", items: [d]),
        ])
        let present: Set<String> = ["00.png", "01.png", "02.png"]
        #expect(CounterNumbering.numbers(in: sidecar, present: present) == [a.id: 1, b.id: 2, c.id: 1, d.id: 2])
        sidecar.counter = "step"
        #expect(CounterNumbering.numbers(in: sidecar, present: present) == [a.id: 1, b.id: 2, c.id: 1, d.id: 1])
        sidecar.counter = "something-newer"
        #expect(CounterNumbering.numbers(in: sidecar, present: present) == [a.id: 1, b.id: 2, c.id: 1, d.id: 2])
    }

    @Test func theDocumentNumbersItsPresentSteps() throws {
        let temp = try TempFolder()
        var document = try CaseDocument.load(folder: try temp.copy(fixture: "poc-sample-vm-migrate"))
        let (a, b) = (counter(), counter())
        document.sidecar.steps[0].items = [a]
        document.sidecar.steps[2].items = [b]
        document.sidecar.steps.insert(SidecarStep(file: "gone.png", items: [counter()]), at: 1)
        #expect(document.counterNumbers == [a.id: 1, b.id: 2])
    }

    @Test func presetsCarryThePaletteColours() {
        #expect(Styles.builtIn.style(for: 1).color == RGBA(hex: 0x00579C))
        #expect(Styles.builtIn.style(for: 2).color == RGBA(hex: 0xC62828))
        #expect(Styles.builtIn.style(for: 3).color == RGBA(hex: 0x00897B))
        #expect(RGBA(hex: 0xFF8000, alpha: 0.5) == RGBA(red: 1, green: 128.0 / 255, blue: 0, alpha: 0.5))
    }
}
