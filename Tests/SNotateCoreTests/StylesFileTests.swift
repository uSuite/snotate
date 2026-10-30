import CoreGraphics
import Testing
@testable import SNotateCore

struct StylesFileTests {
    @Test func theShippedFileIsExactlyTheBuiltInPresets() {
        let (styles, issues) = StylesFile.parse(StylesFile.defaultText)
        #expect(issues.isEmpty)
        #expect(styles == Styles.builtIn)
    }

    @Test func aBlockNamesOnlyWhatDiffersAndAddsPresets() {
        let (styles, issues) = StylesFile.parse("""
            preset 1
            color #1E5EFF

            preset 4
            color #6A1B9A
            counter 40
            """)
        #expect(issues.isEmpty)
        var one = Styles.builtIn.presets[1]!
        one.color = RGBA(hex: 0x1E5EFF)
        #expect(styles.presets[1] == one)
        #expect(styles.presets[2] == Styles.builtIn.presets[2])
        var four = Styles.builtIn.presets[1]!
        four.color = RGBA(hex: 0x6A1B9A)
        four.counterRadius = 20
        // Preset 1's values, but not its name.
        four.name = nil
        #expect(styles.presets[4] == four)
        #expect(styles.presets[5] == nil)
    }

    @Test func badLinesAreIssuesAndKeepTheirValue() {
        let (styles, issues) = StylesFile.parse("""
            stroke 3
            preset 2
            color red
            stroke 900
            glow 4
            font 30
            preset 12
            color #000000
            stroke 1
            """)
        var two = Styles.builtIn.presets[2]!
        two.fontSize = 30
        #expect(styles.presets[2] == two)
        #expect(styles.presets.count == 3)
        #expect(issues.map(\.description) == [
            "line 1: stroke comes before any preset line",
            "line 3: color: 'red' is not #rrggbb",
            "line 4: stroke: '900' is not a size from 0.5 to 64 pixels",
            "line 5: unknown style 'glow'",
            "line 7: preset: '12' is not a number from 1 to 9",
        ])
    }
}
