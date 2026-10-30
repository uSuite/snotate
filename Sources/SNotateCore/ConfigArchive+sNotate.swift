import Foundation

/// `:export-config` and the Settings window's Import Config and Export
/// Config (SN-504, SN-506): config, keymap and styles, never state.json, in
/// one `snotate/` folder of a zip, with scommon's `ConfigArchive`.
extension ConfigArchive {
    public static let snotate = ConfigArchive(
        app: "snotate",
        fileNames: ["config", "keymap", "styles"]
    )

    /// The problems sNotate would report in a file a zip brings, as it
    /// reports them for the files on disk.
    @Sendable
    public static func snotateIssues(
        name: String,
        text: String
    ) -> [String] {
        switch name {
        case "config":
            return SNotateConfig.parse(text).issues.map(\.description)
        case "keymap":
            return Keymap<Command>.overlaid(text, over: DefaultKeymap.keymap).issues.map { "\($0)" }
        default:
            return StylesFile.parse(text).issues.map(\.description)
        }
    }
}
