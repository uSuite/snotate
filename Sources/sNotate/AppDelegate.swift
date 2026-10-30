import AppKit
import SNotateCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [CaseWindowController] = []
    private let settings = AppSettings()
    private var openedDuringLaunch = false
    private var launched = false
    /// The keymap and preset names the menu bar shows.
    private var menuKeymap = DefaultKeymap.keymap
    private var menuStyles = Styles.builtIn
    private var settingsWindow: SettingsWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        TestHooks.prepare()
        // Before any open event, so the first window and the menus have the
        // user's keys. Config and keymap edits and :set apply at once
        // (SN-504), the menus too (SN-505).
        settings.start()
        menuKeymap = settings.current.keymap
        menuStyles = settings.current.styles
        NSApp.mainMenu = MainMenu.build(keymap: menuKeymap, styles: menuStyles)
        TestHooks.sayMenus(NSApp.mainMenu)
        settings.onChange = { [weak self] in
            self?.settingsChanged()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        // Paths on the command line arrive as open events when AppKit
        // recognises them; anything it did not deliver is opened here.
        if !openedDuringLaunch {
            let paths = Self.pathArguments(CommandLine.arguments)
            if paths.isEmpty {
                show(CaseWindowController(editor: nil))
            } else {
                paths.forEach(open)
            }
        }
        NSApp.activate()
        if let pane = TestHooks.settingsPane {
            showSettings(pane)
            TestHooks.snapshotSettings(settingsWindow)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if !launched {
            openedDuringLaunch = true
        }
        urls.forEach(open)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        settings.reload()
    }

    /// Every window takes the new settings, and the key one says the first
    /// problem in the files.
    private func settingsChanged() {
        let names = settings.current.styles.presets.mapValues(\.name)
        if settings.current.keymap != menuKeymap || names != menuStyles.presets.mapValues(\.name) {
            menuKeymap = settings.current.keymap
            menuStyles = settings.current.styles
            NSApp.mainMenu = MainMenu.build(keymap: menuKeymap, styles: menuStyles)
            TestHooks.sayMenus(NSApp.mainMenu)
        }
        settingsWindow?.model.refresh()
        controllers.forEach { $0.apply(settings.current) }
        if let summary = settings.issueSummary {
            let key = controllers.first { $0.window?.isKeyWindow == true }
            (key ?? controllers.first)?.show(message: summary)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A case folder or an image in one, in its own window; an empty window
    /// is replaced.
    func open(_ url: URL) {
        let editor: CaseEditor
        do {
            let (document, selected) = try CaseDocument.open(url)
            let file = selected.map { document.steps[$0].file }
            editor = CaseEditor(session: CaseSession(document: document), file: file)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot open \(url.lastPathComponent)"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        // Scripted runs leave the user's Open Recent alone.
        if !TestHooks.isScripted {
            NSDocumentController.shared.noteNewRecentDocumentURL(editor.state.document.folder)
        }
        let empty = controllers.first { $0.isEmpty }
        let controller = CaseWindowController(editor: editor)
        show(controller)
        empty?.close()
        if controllers.count == 1 {
            TestHooks.run(on: controller)
        }
    }

    private func show(_ controller: CaseWindowController) {
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        controller.onSiblingCase = { [weak self, weak controller] offset in
            if let controller {
                self?.openSibling(offset, in: controller)
            }
        }
        controller.canvas.onExportConfig = { [weak self, weak controller] path in
            if let controller {
                self?.exportConfig(to: path, from: controller)
            }
        }
        controller.canvas.onSetOption = { [weak self, weak controller] key, value in
            do {
                try self?.settings.set(key, value)
                controller?.show(message: "\(key) \(value)")
            } catch {
                controller?.show(message: "\(error)")
            }
        }
        controller.apply(settings.current)
        // Problems in the files are said when the first window opens.
        if controllers.isEmpty, let summary = settings.issueSummary {
            controller.show(message: summary)
        }
        controllers.append(controller)
        controller.showWindow(nil)
        controller.refresh()
    }

    /// The case `offset` siblings away in the same window; the window
    /// already showing it comes to the front instead, since two editors on
    /// one sidecar would overwrite each other (DECISIONS 2026-10-27).
    private func openSibling(_ offset: Int, in controller: CaseWindowController) {
        guard let current = controller.editor?.state.document.folder else {
            return
        }
        guard let target = CaseSiblings.sibling(of: current, offset: offset) else {
            controller.show(message: offset > 0 ? "No case after \(current.lastPathComponent)" : "No case before \(current.lastPathComponent)")
            return
        }
        let path = target.standardizedFileURL.path
        if let other = controllers.first(where: { $0.editor?.state.document.folder.standardizedFileURL.path == path }) {
            other.showWindow(nil)
            return
        }
        do {
            let document = try CaseDocument.load(folder: target)
            controller.replace(with: CaseEditor(session: CaseSession(document: document)))
        } catch {
            controller.show(message: "Cannot open \(target.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// `:export-config [path]` and File > Export Config to Desktop: the zip
    /// is written off the main thread, the result said in a toast.
    private func exportConfig(to path: String, from controller: CaseWindowController) {
        let destination = ConfigArchive.snotate.destination(for: path, folder: controller.editor?.state.document.folder)
        let paths = settings.paths
        Task.detached { [weak controller] in
            let message: String
            do {
                let names = try await ConfigArchive.snotate.export(from: paths, to: destination)
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let shown = destination.path.hasPrefix(home) ? "~" + destination.path.dropFirst(home.count) : destination.path
                message = "Exported \(names.count) files to \(shown)"
            } catch {
                message = "\(error)"
            }
            MainQueue.async {
                controller?.show(message: message)
            }
        }
    }

    /// About box (SN-604): version and build from the bundle, the licence,
    /// and where the plain-text settings live.
    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "Image notation for PoC evidence folders.\nMIT licence. Settings in ~/.config/snotate/.\nOriginals are never changed; annotations live in the sidecar.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }

    /// File > Open Recent (SN-505).
    @objc func openRecent(_ sender: Any?) {
        if let url = (sender as? NSMenuItem)?.representedObject as? URL {
            open(url)
        }
    }

    /// sNotate > Settings… (SN-506), one window for the app.
    @objc func showSettings(_ sender: Any?) {
        showSettings(nil)
    }

    private func showSettings(_ pane: SettingsWindowController.Pane?) {
        let controller = settingsWindow ?? SettingsWindowController(app: settings)
        settingsWindow = controller
        controller.show(pane)
    }

    /// The plain-text settings in Finder (SN-504).
    @objc func openConfigFolder(_ sender: Any?) {
        NSWorkspace.shared.open(settings.paths.directory)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.folder, .image]
        panel.message = "Choose a case folder or a capture in one"
        guard panel.runModal() == .OK else {
            return
        }
        panel.urls.forEach(open)
    }

    /// Existing file or folder paths among the arguments, skipping AppKit's
    /// `-Key value` defaults pairs.
    static func pathArguments(_ arguments: [String]) -> [URL] {
        var urls: [URL] = []
        var skipNext = false
        for argument in arguments.dropFirst() {
            if skipNext {
                skipNext = false
                continue
            }
            if argument.hasPrefix("-") {
                skipNext = argument.count > 1
                continue
            }
            let url = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }
        return urls
    }
}
