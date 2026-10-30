import Foundation
import Testing
@testable import SNotateCore

struct SettingsTests {
    private func paths(_ temp: TempFolder) -> ConfigPaths {
        ConfigPaths.snotate(environment: ["XDG_CONFIG_HOME": temp.url.path], home: temp.url)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func noFilesMeansTheDefaults() throws {
        let temp = try TempFolder()
        let settings = Settings.load(paths(temp))
        #expect(settings.config == SNotateConfig())
        #expect(settings.keymap == DefaultKeymap.keymap)
        #expect(settings.issues.isEmpty)
    }

    @Test func theDefaultFilesAreWrittenOnceAndReadBackClean() throws {
        let temp = try TempFolder()
        let paths = paths(temp)
        try Settings.ensureDefaults(paths)
        #expect(try String(contentsOf: paths.keymap, encoding: .utf8) == DefaultKeymap.text)
        #expect(try String(contentsOf: Settings.stylesURL(paths), encoding: .utf8) == StylesFile.defaultText)
        let settings = Settings.load(paths)
        #expect(settings.issues.isEmpty)
        #expect(settings.styles == Styles.builtIn)
        #expect(settings.config == SNotateConfig())
        #expect(settings.keymap == DefaultKeymap.keymap)
        try write("snap false\n", to: paths.config)
        try Settings.ensureDefaults(paths)
        #expect(try String(contentsOf: paths.config, encoding: .utf8) == "snap false\n")
    }

    @Test func theKeymapFileRebindsAndUnbindsOverTheDefaults() throws {
        let temp = try TempFolder()
        let paths = paths(temp)
        try write("x tool arrow\na nop\n1 nop\n", to: paths.keymap)
        let keymap = Settings.load(paths).keymap
        #expect(keymap.command(for: [Key("x")]) == .tool(.arrow))
        #expect(keymap.command(for: [Key("a")]) == nil)
        #expect(keymap.command(for: [Key("1")]) == nil)
        #expect(keymap.command(for: [Key("r")]) == .tool(.rectangle))
    }

    @Test func badLinesAreIssuesAndKeepTheDefault() throws {
        let temp = try TempFolder()
        let paths = paths(temp)
        try write("notated_dir assets\nsnap maybe\ncolour red\nnotated_dir evidence\n", to: paths.config)
        try write("x fly\n", to: paths.keymap)
        let settings = Settings.load(paths)
        #expect(settings.config.notatedDir == "evidence")
        #expect(settings.config.snap)
        #expect(settings.issues == [
            "config line 1: notated_dir: 'assets' is not one plain folder name other than assets",
            "config line 2: snap: 'maybe' is not true or false",
            "config line 3: unknown option 'colour'",
            "keymap line 1: unknown command 'fly'",
        ])
    }

    @Test func stylesAreLoadedWithTheirIssues() throws {
        let temp = try TempFolder()
        let paths = paths(temp)
        try write("preset 4\ncolor #6A1B9A\nglow 2\n", to: Settings.stylesURL(paths))
        let settings = Settings.load(paths)
        #expect(settings.styles.presets[4]?.color == RGBA(hex: 0x6A1B9A))
        #expect(settings.issues == ["styles line 3: unknown style 'glow'"])
    }

    @Test func theDefaultConfigTextParsesToTheDefaults() {
        let (config, issues) = SNotateConfig.parse(SNotateConfig.defaultText)
        #expect(config == SNotateConfig())
        #expect(issues.isEmpty)
    }
}

struct SettingsCommandTests {
    @Test func exportConfigAndSetParseWithTheirWholeArguments() throws {
        #expect(try Command.parse("export-config") == .exportConfig(""))
        #expect(try Command.parse("export-config ~/My Backups/s.zip") == .exportConfig("~/My Backups/s.zip"))
        #expect(try Command.parseCommandLine("set snap false") == .setOption("snap", "false"))
        #expect(try Command.parse("set notated_dir out folder") == .setOption("notated_dir", "out folder"))
        #expect(throws: CommandError.badArgument("set needs a key and a value")) {
            try Command.parse("set snap")
        }
        #expect(Command.setOption("snap", "false").name == "set snap false")
        #expect(Command.exportConfig("").name == "export-config")
    }

    @Test func theyAreEffectsForTheAppAndWorkWithoutImages() throws {
        let temp = try TempFolder()
        var state = EditorState(document: try CaseDocument.load(folder: try temp.folder("poc-demo-vm-empty")))
        #expect(Dispatcher.apply(Invocation(.exportConfig("x.zip")), to: &state) == [.exportConfig("x.zip")])
        #expect(Dispatcher.apply(Invocation(.setOption("snap", "off")), to: &state) == [.setOption("snap", "off")])
    }
}

struct PresetStyleTests {
    @Test func aPresetTheStylesLackIsRefusedWithAMessage() throws {
        var fixture = try EditorFixture(items: [Annotation(shape: .counter(at: .zero))])
        #expect(fixture.run(.preset(7)) == [.message("No preset 7 in styles")])
        #expect(fixture.state.activePreset == 1)
        fixture.state.styles.presets[7] = Styles.builtIn.presets[2]
        #expect(fixture.run(.preset(7)).isEmpty)
        #expect(fixture.state.activePreset == 7)
    }

    @Test func headlessExportDrawsWithTheLoadedStyles() throws {
        let annotated = try AnnotatedCase()
        var plain: [String] = []
        _ = HeadlessExport.run([annotated.folder.path]) { plain.append($0) }
        let file = annotated.folder.appendingPathComponent("notated/\(AnnotatedCase.file(0))")
        let before = try Data(contentsOf: file)
        var settings = Settings()
        settings.styles.presets[1]?.color = RGBA(hex: 0x6A1B9A)
        settings.styles.presets[2]?.color = RGBA(hex: 0x6A1B9A)
        var lines: [String] = []
        _ = HeadlessExport.run([annotated.folder.path], settings: settings) { lines.append($0) }
        #expect(lines.contains("  wrote notated/\(AnnotatedCase.file(0))"))
        #expect(try Data(contentsOf: file) != before)
    }
}
