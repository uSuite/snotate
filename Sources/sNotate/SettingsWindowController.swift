import AppKit
import SNotateCore
import SwiftUI
import UniformTypeIdentifiers

/// What the Settings window shows and does (SN-506). The files stay the
/// truth: every change is written to `config` or `styles` through
/// `AppSettings`, whose reload brings it back here and to every case
/// window, as a hand edit or `:set` does.
@MainActor
@Observable
final class SettingsModel {
    var settings: SNotateCore.Settings
    var selectedSlot = 1
    /// The last thing an action did, under the buttons that did it.
    var status = ""
    @ObservationIgnored let app: AppSettings
    /// Preset edits not yet written, so the preview follows every change
    /// while the file is written once the edits pause.
    private var pending: [Int: Style] = [:]
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(app: AppSettings) {
        self.app = app
        settings = app.current
    }

    func refresh() {
        settings = app.current
    }

    var problems: [String] { settings.issues }

    /// The preset in `slot`, with an edit still waiting.
    func style(_ slot: Int) -> Style? {
        pending[slot] ?? settings.styles.presets[slot]
    }

    func isBuiltIn(_ slot: Int) -> Bool {
        Styles.builtIn.presets[slot] != nil
    }

    func update(
        _ slot: Int,
        _ change: (inout Style) -> Void
    ) {
        guard var style = style(slot) else {
            return
        }
        change(&style)
        guard style != self.style(slot) else {
            return
        }
        pending[slot] = style
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            self?.flush()
        }
    }

    /// Writes waiting edits now; the window calls it when it closes.
    func flush() {
        writeTask?.cancel()
        writeTask = nil
        guard !pending.isEmpty else {
            return
        }
        var text = app.stylesText
        for (slot, style) in pending.sorted(by: { $0.key < $1.key }) {
            text = StylesEdit.setting(slot, to: style, in: text)
        }
        pending = [:]
        write(text)
    }

    /// `style` into `slot` at once, selected.
    func save(
        _ style: Style,
        to slot: Int
    ) {
        flush()
        write(StylesEdit.setting(slot, to: style, in: app.stylesText))
        selectedSlot = slot
    }

    /// A copy of the selected preset (or preset 1) in the lowest free slot.
    func addPreset() {
        guard let slot = StylesEdit.freeSlot(in: settings.styles) else {
            status = "All nine presets are set"
            return
        }
        var style = self.style(selectedSlot) ?? settings.styles.style(for: 1)
        style.name = style.name.map { String(("\($0) copy").prefix(StylesFile.nameLimit)) }
        save(style, to: slot)
        status = "Preset \(slot) added"
    }

    /// Takes the slot's block out of the file: built-in presets come back,
    /// others are unset and their annotations draw as preset 1.
    func removePreset(_ slot: Int) {
        flush()
        write(StylesEdit.removing(slot, in: app.stylesText))
        status = isBuiltIn(slot) ? "Preset \(slot) is the built-in one again" : "Preset \(slot) removed"
    }

    private func write(_ text: String) {
        do {
            try app.writeStyles(text)
        } catch {
            status = "Styles not saved: \(error.localizedDescription)"
        }
        refresh()
    }

    func setSnap(_ on: Bool) {
        do {
            try app.set("snap", on ? "true" : "false")
        } catch {
            status = "\(error)"
        }
        refresh()
    }
}

/// sNotate > Settings… (SN-506): the macOS Settings look, a toolbar of
/// panes, General and Presets, each a SwiftUI view.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Pane: String, CaseIterable {
        case general
        case presets
    }

    let model: SettingsModel
    private let tabs = NSTabViewController()

    init(app: AppSettings) {
        model = SettingsModel(app: app)
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        super.init(window: window)
        add(GeneralSettingsView(model: model), label: "General", symbol: "gearshape")
        add(PresetsSettingsView(model: model), label: "Presets", symbol: "paintpalette")
        window.delegate = self
        window.setFrameAutosaveName("Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private func add(
        _ view: some View,
        label: String,
        symbol: String
    ) {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        // The tab view controller shows the pane's title as the window's.
        hosting.title = label
        let item = NSTabViewItem(viewController: hosting)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        tabs.addTabViewItem(item)
    }

    func show(_ pane: Pane? = nil) {
        if let pane, let index = Pane.allCases.firstIndex(of: pane) {
            tabs.selectedTabViewItemIndex = index
        }
        model.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model.flush()
    }
}

/// The file panels and alerts both panes use.
@MainActor
enum SettingsPanels {
    static let presetType = UTType(filenameExtension: PresetFile.fileExtension) ?? .plainText

    /// Import Config…: the zip is read and checked first, then the files it
    /// replaces are named with their problems before anything changes.
    static func importConfig(_ model: SettingsModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.message = "Choose a config zip made by Export Config"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task {
            let files: [ConfigArchive.File]
            do {
                files = try await ConfigArchive.snotate.inspect(url, check: ConfigArchive.snotateIssues)
            } catch {
                model.status = "\(error)"
                return
            }
            let names = files.map(\.name)
            let alert = NSAlert()
            alert.messageText = "Replace \(list(names)) with the ones in \(url.lastPathComponent)?"
            var info = "The current files are kept as \(list(names.map { $0 + ".bak" })) in the config folder."
            for file in files where !file.issues.isEmpty {
                info += "\n\n\(file.name):\n" + file.issues.prefix(5).joined(separator: "\n")
                if file.issues.count > 5 {
                    info += "\n(+\(file.issues.count - 5) more)"
                }
            }
            alert.informativeText = info
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
            do {
                let written = try model.app.importConfig(files)
                model.status = "Imported \(list(written)); the old files are kept as .bak"
            } catch {
                model.status = "\(error)"
            }
            model.refresh()
        }
    }

    /// Export Config…: the zip `:export-config` writes, where the author
    /// chooses.
    static func exportConfig(_ model: SettingsModel) {
        let suggested = ConfigArchive.snotate.destination(for: "", folder: nil)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let paths = model.app.paths
        Task {
            do {
                let names = try await ConfigArchive.snotate.export(from: paths, to: url)
                model.status = "Exported \(names.count) files to \(url.lastPathComponent)"
            } catch {
                model.status = "\(error)"
            }
        }
    }

    /// Import Preset…: problems are shown, then the slot is chosen.
    static func importPreset(_ model: SettingsModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [presetType]
        panel.message = "Choose a .\(PresetFile.fileExtension) file"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            model.status = "\(url.lastPathComponent) is not UTF-8 text"
            return
        }
        let (style, issues) = PresetFile.parse(text)
        let alert = NSAlert()
        alert.messageText = "Import \(style.name ?? url.deletingPathExtension().lastPathComponent) as preset:"
        alert.informativeText = issues.isEmpty
            ? "A preset already in that slot is replaced."
            : "Lines kept at their defaults:\n" + issues.map(\.description).joined(separator: "\n")
        let slots = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        for slot in 1...9 {
            let current = model.settings.styles.presets[slot]
            slots.addItem(withTitle: "\(slot)" + (current.map { ": " + ($0.name ?? "unnamed") } ?? ": not set"))
        }
        let target = StylesEdit.freeSlot(in: model.settings.styles) ?? model.selectedSlot
        slots.selectItem(at: target - 1)
        alert.accessoryView = slots
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        let slot = slots.indexOfSelectedItem + 1
        model.save(style, to: slot)
        model.status = "Imported \(url.lastPathComponent) as preset \(slot)"
    }

    static func exportPreset(
        _ model: SettingsModel,
        slot: Int
    ) {
        guard let style = model.style(slot) else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [presetType]
        panel.nameFieldStringValue = PresetFile.suggestedName(for: style, slot: slot)
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try Data(PresetFile.text(of: style).utf8).write(to: url, options: .atomic)
            model.status = "Exported preset \(slot) to \(url.lastPathComponent)"
        } catch {
            model.status = "Not exported: \(error.localizedDescription)"
        }
    }

    static func confirmRemove(
        _ model: SettingsModel,
        slot: Int
    ) {
        let alert = NSAlert()
        if model.isBuiltIn(slot) {
            alert.messageText = "Revert preset \(slot) to the built-in one?"
            alert.informativeText = "Its block is taken out of the styles file."
            alert.addButton(withTitle: "Revert")
        } else {
            alert.messageText = "Remove preset \(slot)?"
            alert.informativeText = "Annotations that use it draw as preset 1 until it is set again."
            alert.addButton(withTitle: "Remove")
        }
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.removePreset(slot)
        }
    }

    private static func list(_ names: [String]) -> String {
        guard names.count > 1 else {
            return names.first ?? ""
        }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}
