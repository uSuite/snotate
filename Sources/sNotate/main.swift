import AppKit
import SNotateCore

// `--export <case-folder>...` exports headless and never starts the app.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--export") {
    exit(HeadlessExport.run(Array(arguments[(flag + 1)...]), settings: Settings.load(.snotate())) { print($0) })
}

// AppKit lifecycle (DECISIONS 2026-10-26): an explicit delegate receives
// open-document events for Finder, `open -a` and argv paths.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
