import AppKit
import SNotateCore

/// The config, keymap and styles every window uses (SN-504, SN-210), read from
/// `~/.config/snotate/` and read again when a file there changes or the
/// app becomes active, so edits and `:set` apply at once.
@MainActor
final class AppSettings {
    let paths = ConfigPaths.snotate()
    private(set) var current = Settings()
    /// After a reload that changed something.
    var onChange: (() -> Void)?
    private var watcher: DirectoryWatcher?

    /// Writes the missing default files, reads them and starts watching.
    func start() {
        try? Settings.ensureDefaults(paths)
        current = Settings.load(paths)
        watcher = DirectoryWatcher(
            url: paths.directory,
            files: ["config", "keymap", "styles"]
        ) { [weak self] in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
    }

    func reload() {
        let fresh = Settings.load(paths)
        guard fresh != current else {
            return
        }
        current = fresh
        onChange?()
    }

    /// The first problem in the files, for a toast.
    var issueSummary: String? {
        guard let first = current.issues.first else {
            return nil
        }
        return current.issues.count > 1 ? "\(first) (+\(current.issues.count - 1) more)" : first
    }

    /// `:set`: checked, written as one line of the config file, applied.
    func set(_ key: String, _ value: String) throws {
        try paths.persist(key, value, as: SNotateConfig.self)
        reload()
    }

    var stylesURL: URL { Settings.stylesURL(paths) }

    /// The styles file as it is on disk, the defaults when there is none.
    var stylesText: String {
        (try? String(contentsOf: stylesURL, encoding: .utf8)) ?? StylesFile.defaultText
    }

    /// The Settings window's preset edits (SN-506): the whole styles text,
    /// already edited block by block, written and applied at once.
    func writeStyles(_ text: String) throws {
        try Data(text.utf8).write(to: stylesURL, options: .atomic)
        reload()
    }

    /// A checked config zip into the folder, the replaced files kept as
    /// `.bak` (SN-506).
    func importConfig(_ files: [ConfigArchive.File]) throws -> [String] {
        let names = try ConfigArchive.apply(files, to: paths.directory)
        reload()
        return names
    }
}
