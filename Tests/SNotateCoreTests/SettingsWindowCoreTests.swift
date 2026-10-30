import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct StylesEditTests {
    private let defaults = StylesFile.defaultText

    @Test func theDefaultFileNamesTheBuiltInPresets() {
        let (styles, issues) = StylesFile.parse(defaults)
        #expect(issues.isEmpty)
        #expect(styles == Styles.builtIn)
        #expect(styles.presets[2]?.name == "Danger")
        // A file without names keeps the built-in ones.
        #expect(StylesFile.parse("preset 2\ncolor #000000\n").styles.presets[2]?.name == "Danger")
    }

    @Test func aNameIsOneToFortyCharacters() {
        let (styles, issues) = StylesFile.parse("preset 4\nname Hostname # blur\npreset 5\nname \(String(repeating: "x", count: 41))\n")
        #expect(styles.presets[4]?.name == "Hostname # blur")
        #expect(issues.map(\.description) == ["line 4: name: '\(String(repeating: "x", count: 41))' is not 1 to 40 characters"])
    }

    @Test func settingAPresetChangesOnlyItsBlock() {
        var style = Styles.builtIn.style(for: 2)
        style.color = RGBA(hex: 0x123456)
        style.strokeWidth = 7.5
        let edited = StylesEdit.setting(2, to: style, in: defaults)
        #expect(StylesFile.parse(edited).styles.presets[2] == style)
        let before = defaults.split(separator: "\n", omittingEmptySubsequences: false)
        let after = edited.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(before.count == after.count)
        let changed = zip(before, after).filter { $0 != $1 }.map { String($0.1) }
        #expect(changed == ["color #123456", "stroke 7.5"])
    }

    @Test func missingLinesGoAfterTheBlocksLastLineAndCommentsStay() {
        let text = "# mine\npreset 2\n# red, for errors\ncolor #FF0000\n\n# next\npreset 3\nstroke 1\n"
        var style = StylesFile.parse(text).styles.style(for: 2)
        style.name = "Errors"
        let edited = StylesEdit.setting(2, to: style, in: text)
        #expect(edited == "# mine\npreset 2\n# red, for errors\ncolor #FF0000\nname Errors\nstroke 6\nfont 36\ncounter 48\nblur 16\n\n# next\npreset 3\nstroke 1\n")
        #expect(StylesFile.parse(edited).styles.presets[2] == style)
    }

    @Test func aNewPresetGetsABlockAtTheEnd() {
        var style = Styles.builtIn.style(for: 1)
        style.name = "Hostname"
        let edited = StylesEdit.setting(4, to: style, in: defaults)
        #expect(edited.hasPrefix(defaults))
        #expect(edited.hasSuffix("\n\npreset 4\nname Hostname\ncolor #00579C\nstroke 4\nfont 28\ncounter 36\nblur 12\n"))
        #expect(StylesFile.parse(edited).styles.presets[4] == style)
        #expect(StylesEdit.setting(4, to: style, in: "") == "preset 4\nname Hostname\ncolor #00579C\nstroke 4\nfont 28\ncounter 36\nblur 12\n")
    }

    @Test func droppingTheNameRemovesItFromEveryBlock() {
        let text = "preset 4\nname Old\npreset 4\nstroke 3\n"
        var style = StylesFile.parse(text).styles.style(for: 4)
        style.name = nil
        let edited = StylesEdit.setting(4, to: style, in: text)
        #expect(!edited.contains("name"))
        #expect(StylesFile.parse(edited).styles.presets[4]?.name == nil)
    }

    @Test func removingAPresetBringsTheBuiltInBack() {
        var red = Styles.builtIn.style(for: 2)
        red.color = RGBA(hex: 0x000000)
        let custom = StylesEdit.setting(4, to: red, in: StylesEdit.setting(2, to: red, in: defaults))
        let removed = StylesEdit.removing(4, in: StylesEdit.removing(2, in: custom))
        let styles = StylesFile.parse(removed).styles
        #expect(styles.presets[2] == Styles.builtIn.presets[2])
        #expect(styles.presets[4] == nil)
        #expect(!removed.contains("preset 2"))
        #expect(removed.contains("preset 1") && removed.contains("preset 3"))
    }

    @Test func theFreeSlotIsTheLowestUnset() {
        #expect(StylesEdit.freeSlot(in: .builtIn) == 4)
        var full = Styles.builtIn
        for n in 4...9 {
            full.presets[n] = full.style(for: 1)
        }
        #expect(StylesEdit.freeSlot(in: full) == nil)
    }

    @Test func numbersAndColoursAreWrittenAsTheParserReadsThem() {
        #expect(StylesEdit.number(4) == "4")
        #expect(StylesEdit.number(0.5) == "0.5")
        #expect(StylesEdit.number(2.3333) == "2.33")
        #expect(StylesEdit.hex(RGBA(red: 1, green: 0.5, blue: 0)) == "#FF8000")
    }
}

struct PresetFileTests {
    @Test(arguments: [1, 2, 3])
    func everyBuiltInRoundTrips(slot: Int) {
        let style = Styles.builtIn.style(for: slot)
        let text = PresetFile.text(of: style)
        #expect(text.hasPrefix("# sNotate preset"))
        #expect(!text.contains("preset \(slot)"))
        let parsed = PresetFile.parse(text)
        #expect(parsed.issues.isEmpty)
        #expect(parsed.style == style)
    }

    @Test func aPartialFileFillsFromPresetOneWithoutItsName() {
        let style = PresetFile.parse("color #FF0000\n").style
        #expect(style.color == RGBA(hex: 0xFF0000))
        #expect(style.strokeWidth == 4)
        #expect(style.name == nil)
    }

    @Test func aPresetLineOrABadValueIsAnIssue() {
        let issues = PresetFile.parse("preset 2\nstroke 900\nname Ok\n").issues.map(\.description)
        #expect(issues == [
            "line 1: a preset file holds one preset and no preset line",
            "line 2: stroke: '900' is not a size from 0.5 to 64 pixels",
        ])
    }

    @Test func theSuggestedNameIsSafeForAFile() {
        var style = Styles.builtIn.style(for: 2)
        #expect(PresetFile.suggestedName(for: style, slot: 2) == "Danger.snotatepreset")
        style.name = "IP / host: blur"
        #expect(PresetFile.suggestedName(for: style, slot: 2) == "IP - host- blur.snotatepreset")
        style.name = nil
        #expect(PresetFile.suggestedName(for: style, slot: 7) == "preset-7.snotatepreset")
    }
}

/// The shared ConfigArchive is tested in scommon; this is sNotate's setup.
struct ConfigArchiveSetupTests {
    @Test func stylesTravelAndEachFileIsCheckedAsTheAppDoes() async throws {
        let temp = try TempFolder()
        let paths = ConfigPaths(directory: temp.url.appendingPathComponent("snotate"))
        try paths.ensureDefaults(config: "snap true\n", keymap: "n next\n")
        try Data("preset 2\ncolor red\n".utf8).write(to: paths.directory.appendingPathComponent("styles"))
        let zip = temp.url.appendingPathComponent("out.zip")
        let names = try await ConfigArchive.snotate.export(from: paths, to: zip)
        #expect(names == ["snotate/config", "snotate/keymap", "snotate/styles"])
        let files = try await ConfigArchive.snotate.inspect(zip, check: ConfigArchive.snotateIssues)
        #expect(files.map(\.name) == ["config", "keymap", "styles"])
        #expect(files.map(\.issues) == [[], [], ["line 2: color: 'red' is not #rrggbb"]])
        #expect(ConfigArchive.snotateIssues(name: "config", text: "snap maybe\n") == ["line 1: snap: 'maybe' is not true or false"])
        #expect(ConfigArchive.Failure.nothingToExport(ConfigArchive.snotate.listed).description == "no config, keymap or styles to export")
        #expect(ConfigArchive.snotate.destination(for: "", folder: nil).lastPathComponent.hasPrefix("snotate-config-"))
    }
}

struct PresetPreviewTests {
    @Test func thePreviewDrawsThePresetsColour() throws {
        let blue = PresetPreview.render(Styles.builtIn.style(for: 1))
        let red = PresetPreview.render(Styles.builtIn.style(for: 2))
        #expect(blue.width == PresetPreview.width && blue.height == PresetPreview.height)
        #expect(Renderer.pngData(blue) != Renderer.pngData(red))
        #expect(Renderer.pngData(blue) == Renderer.pngData(PresetPreview.render(Styles.builtIn.style(for: 1))))
    }
}
