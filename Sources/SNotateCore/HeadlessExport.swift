import Foundation

/// `sNotate --export <case-folder>...`: exports each case into its
/// `notated/` without starting the app, one indented line per file, then a
/// summary. A folder that cannot be exported is an error line and the rest
/// still export; the exit status is 1 when anything was refused, 2 when no
/// folder was given. A path to an image exports the case it belongs to. A
/// folder that is not itself a case is a PoC root (SN-405): every case under
/// it with a sidecar is exported, the others are counted, and a last line
/// totals the tree. The config's `notated_dir` and export options apply here
/// as in the app; problems in the config files are warnings and do not
/// change the status.
public enum HeadlessExport {
    public static func run(
        _ paths: [String],
        settings: Settings = Settings(),
        print: (String) -> Void
    ) -> Int32 {
        guard !paths.isEmpty else {
            print("usage: sNotate --export <case-folder or poc-root>...")
            return 2
        }
        for issue in settings.issues {
            print("warning: " + issue)
        }
        var status: Int32 = 0
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue, !CaseWalker.isCase(url) {
                let found = CaseWalker.cases(under: url, notatedDir: settings.config.notatedDir)
                var failed = 0
                for folder in found.withSidecar where !export(folder, path: folder.path, settings: settings, print: print) {
                    failed += 1
                }
                let exported = found.withSidecar.count - failed
                print("\(path): \(exported) case\(exported == 1 ? "" : "s") exported, \(found.withoutSidecar.count) without a sidecar skipped, \(failed) failed")
                if failed > 0 {
                    status = 1
                }
            } else if !export(url, path: path, settings: settings, print: print) {
                status = 1
            }
        }
        return status
    }

    /// One case and its report; `false` when it could not be exported.
    private static func export(
        _ url: URL,
        path: String,
        settings: Settings,
        print: (String) -> Void
    ) -> Bool {
        do {
            let document = try CaseDocument.open(url).document
            let report = try Exporter.exportCase(
                document,
                styles: settings.styles,
                folderName: settings.config.notatedDir,
                options: ExportOptions(config: settings.config)
            )
            print(document.caseID)
            for line in lines(report) {
                print("  " + line)
            }
            return true
        } catch {
            print("error: \(path): \(error)")
            return false
        }
    }

    static func lines(_ report: ExportReport) -> [String] {
        report.written.map { "wrote " + $0 }
            + report.excluded.map { "excluded " + $0 }
            + report.unchanged.map { "unchanged " + $0 }
            + report.removed.map { "removed " + $0 }
            + report.skipped.map { "skipped \($0.file): \($0.reason)" }
            + report.warnings.map { "warning: " + $0 }
            + [report.summary]
    }
}
