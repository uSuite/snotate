import Foundation

/// Settings from `~/.config/snotate/config` (SN-504). Only keys with
/// something behind them are accepted; `export_scale`, `counter` and `grid`
/// arrive with their features. Unknown keys and bad values are issues and
/// keep the default, so a typo never stops the app (DECISIONS 2026-10-27).
public struct SNotateConfig: KeyValueSettings, Equatable {
    /// The export folder inside each case, `notated` by default.
    public var notatedDir = ExportPlan.defaultFolder
    /// Snapping to image edges and other annotations while drawing.
    public var snap = true
    /// Export options (SN-403); see `ExportOptions`.
    public var exportScale: CGFloat = 1
    public var exportFormat = ExportOptions.Format.png
    public var jpegQuality = 90
    public var exportCounters = true
    public var exportCaptions = false
    public var exportSheet = ExportOptions.Sheet.off
    public var exportTypst = false
    public var typstImport: String?
    public var exportLabels = ExportOptions.Labels.both

    public init() {}

    public enum SetError: Error, Equatable, CustomStringConvertible {
        case unknownKey(String)
        case badValue(key: String, value: String, expected: String)

        public var description: String {
            switch self {
            case .unknownKey(let key):
                return "unknown option '\(key)'"
            case .badValue(let key, let value, let expected):
                return "\(key): '\(value)' is not \(expected)"
            }
        }
    }

    /// Applies one `key value` pair, the same path `:set` uses.
    public mutating func set(_ key: String, _ value: String) throws(SetError) {
        switch key {
        case "notated_dir":
            guard ExportPlan.isFolderName(value) else {
                throw .badValue(key: key, value: value, expected: "one plain folder name other than assets")
            }
            notatedDir = value
        case "snap":
            snap = try Self.bool(key, value)
        case "export_scale":
            guard let scale = Double(value).map({ CGFloat($0) }), ExportOptions.scales.contains(scale) else {
                throw .badValue(key: key, value: value, expected: "0.5, 1 or 2")
            }
            exportScale = scale
        case "export_format":
            guard let format = ExportOptions.Format(rawValue: value.lowercased()) else {
                throw .badValue(key: key, value: value, expected: "png or jpeg")
            }
            exportFormat = format
        case "jpeg_quality":
            guard let quality = Int(value), (1...100).contains(quality) else {
                throw .badValue(key: key, value: value, expected: "a whole number from 1 to 100")
            }
            jpegQuality = quality
        case "export_counters":
            exportCounters = try Self.bool(key, value)
        case "export_captions":
            exportCaptions = try Self.bool(key, value)
        case "export_sheet":
            guard let sheet = ExportOptions.Sheet(rawValue: value.lowercased()) else {
                throw .badValue(key: key, value: value, expected: "off, png, pdf or both")
            }
            exportSheet = sheet
        case "export_typst":
            exportTypst = try Self.bool(key, value)
        case "typst_import":
            if value.lowercased() == "none" {
                typstImport = nil
            } else {
                guard value.wholeMatch(of: /@[a-z0-9-]+\/[a-z0-9-]+:\d+\.\d+\.\d+/) != nil else {
                    throw .badValue(key: key, value: value, expected: "none or a package such as @local/memo:1.0.0")
                }
                typstImport = value
            }
        case "export_labels":
            guard let labels = ExportOptions.Labels(rawValue: value.lowercased()) else {
                throw .badValue(key: key, value: value, expected: "off, md, yaml or both")
            }
            exportLabels = labels
        default:
            throw .unknownKey(key)
        }
    }

    private static func bool(_ key: String, _ value: String) throws(SetError) -> Bool {
        switch value.lowercased() {
        case "true", "yes", "on", "1":
            return true
        case "false", "no", "off", "0":
            return false
        default:
            throw .badValue(key: key, value: value, expected: "true or false")
        }
    }

    public static let defaultText = """
        # sNotate config. One setting per line: <key> <value>; # starts a comment.
        # Edits apply at once; a bad line is reported and keeps the default.

        # The folder inside each case that export writes to.
        notated_dir notated

        # Snap to image edges and other annotations while drawing (shift
        # also turns it off for one drag).
        snap true

        # Export: times the native pixel size (0.5, 1 or 2), png or jpeg and
        # its quality, step counters, and captions burned under the image.
        export_scale 1
        export_format png
        jpeg_quality 90
        export_counters true
        export_captions false

        # The case on one page in notated/ (off, png, pdf or both), and
        # notated/<case-id>.typ with one #shot per step for a Typst memo.
        export_sheet off
        export_typst false
        # The Typst package the fragment imports #shot from, such as
        # @local/memo:1.0.0, or none for a plain figure per step.
        typst_import none

        # The steps' captions beside the images: notated/<case-id>.md in the
        # evidence script's shape and notated/<case-id>.yaml (off, md, yaml
        # or both).
        export_labels both

        """
}

/// The config, keymap and styles as read from the config folder, with
/// every problem found in them, prefixed by its file.
public struct Settings: Sendable, Equatable {
    public var config = SNotateConfig()
    public var keymap = DefaultKeymap.keymap
    public var styles = Styles.builtIn
    public var issues: [String] = []

    public init() {}

    /// Missing files mean the defaults; the keymap file is laid over the
    /// built-in bindings, so `<keys> nop` unbinds.
    public static func load(_ paths: ConfigPaths) -> Settings {
        var settings = Settings()
        let (config, configIssues) = paths.load(SNotateConfig.self)
        settings.config = config
        settings.issues = configIssues.map { "config \($0)" }
        if let text = try? String(contentsOf: paths.keymap, encoding: .utf8) {
            let (keymap, keymapIssues) = Keymap<Command>.overlaid(text, over: DefaultKeymap.keymap)
            settings.keymap = keymap
            settings.issues += keymapIssues.map { "keymap \($0)" }
        }
        if let text = try? String(contentsOf: stylesURL(paths), encoding: .utf8) {
            let (styles, stylesIssues) = StylesFile.parse(text)
            settings.styles = styles
            settings.issues += stylesIssues.map { "styles \($0)" }
        }
        return settings
    }

    public static func stylesURL(_ paths: ConfigPaths) -> URL {
        paths.directory.appendingPathComponent("styles")
    }

    /// The default files, written when missing and never over the user's.
    public static func ensureDefaults(_ paths: ConfigPaths) throws {
        try paths.ensureDefaults(config: SNotateConfig.defaultText, keymap: DefaultKeymap.text)
        let styles = stylesURL(paths)
        if !FileManager.default.fileExists(atPath: styles.path) {
            try Data(StylesFile.defaultText.utf8).write(to: styles, options: .atomic)
        }
    }
}
