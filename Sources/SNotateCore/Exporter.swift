import Foundation

/// What an export did, paths relative to the case folder.
public struct ExportReport: Sendable, Equatable {
    public var written: [String] = []
    public var unchanged: [String] = []
    public var removed: [String] = []
    public var skipped: [ExportPlan.Skipped] = []
    /// Excluded steps, listed for the author to delete (SN-305).
    public var excluded: [String] = []

    public var warnings: [String] = []

    /// One line for a toast or the end of a headless report.
    public var summary: String {
        var line = "\(written.count) written, \(unchanged.count) unchanged, \(removed.count) removed, \(skipped.count) skipped"
        if !excluded.isEmpty {
            line += ", \(excluded.count) excluded"
        }
        if !warnings.isEmpty {
            line += ", \(warnings.count) warning\(warnings.count == 1 ? "" : "s")"
        }
        return line
    }
}

/// Export into `notated/` (SN-401, SN-402 core). Each file is rendered by
/// the one Renderer with the whole case's counter numbers and written only
/// when its bytes change, so a second export touches nothing. A case export
/// then removes the `.png` and `.jpg` files in `notated/` and
/// `notated/assets/` that are no longer part of it, so a change of format
/// leaves no orphans, and nothing else there (DECISIONS 2026-10-26,
/// 2026-10-27). `options` are the config's (SN-403).
public enum Exporter {
    public static func exportCase(
        _ document: CaseDocument,
        styles: Styles = .builtIn,
        folderName: String = ExportPlan.defaultFolder,
        options: ExportOptions = ExportOptions()
    ) throws(ExportError) -> ExportReport {
        let plan = try ExportPlan(document: document, folderName: folderName, format: options.format)
        var report = ExportReport(skipped: plan.skipped, warnings: warnings(document, files: plan.targets.map(\.file)))
        report.excluded = document.steps.filter(\.excluded).map(\.file)
        let numbers = document.counterNumbers
        for target in plan.targets {
            guard let data = render(target.file, of: document, styles: styles, numbers: numbers, options: options) else {
                report.skipped.append(ExportPlan.Skipped(file: target.file, reason: "image cannot be decoded"))
                continue
            }
            try write(data, to: target, report: &report)
        }
        let kept = try exportCaseFiles(document, plan: plan, styles: styles, options: options, report: &report)
        report.removed = try removeStale(plan, keeping: kept) + report.removed
        report.removed.sort()
        return report
    }

    /// The contact sheet, Typst fragment (SN-404) and labels (SN-407) the
    /// options ask for, written only when they change; the ones turned off
    /// are removed when they are ours. Returns the PNG sheet's path, so the
    /// stale cleanup keeps it.
    private static func exportCaseFiles(
        _ document: CaseDocument,
        plan: ExportPlan,
        styles: Styles,
        options: ExportOptions,
        report: inout ExportReport
    ) throws(ExportError) -> Set<String> {
        let files = plan.targets.map(\.file)
        let name = document.caseID
        func target(_ fileName: String) -> ExportPlan.Target {
            ExportPlan.Target(
                file: fileName,
                relative: plan.folder.lastPathComponent + "/" + fileName,
                output: plan.folder.appendingPathComponent(fileName)
            )
        }
        func remove(_ target: ExportPlan.Target, if isOurs: (URL) -> Bool) throws(ExportError) {
            guard FileManager.default.fileExists(atPath: target.output.path), isOurs(target.output) else {
                return
            }
            do {
                try FileManager.default.removeItem(at: target.output)
            } catch {
                throw .writeFailed("\(target.relative): \(error.localizedDescription)")
            }
            report.removed.append(target.relative)
        }
        var kept: Set<String> = []
        let png = target(name + "-sheet.png")
        let pdf = target(name + "-sheet.pdf")
        if options.sheet != .off, let sheet = ContactSheet.png(document, files: files, styles: styles, options: options) {
            if options.sheet == .png || options.sheet == .both {
                try write(sheet.data, to: png, report: &report)
                kept.insert(png.output.standardizedFileURL.path)
            }
            if options.sheet == .pdf || options.sheet == .both {
                if ContactSheet.recordedFingerprint(at: pdf.output) == sheet.fingerprint {
                    report.unchanged.append(pdf.relative)
                } else if let data = ContactSheet.pdf(document, files: files, styles: styles, options: options, fingerprint: sheet.fingerprint) {
                    try write(data, to: pdf, report: &report)
                }
            } else {
                try remove(pdf) { ContactSheet.recordedFingerprint(at: $0) != nil }
            }
        } else {
            try remove(pdf) { ContactSheet.recordedFingerprint(at: $0) != nil }
        }
        // Only what was written: a step whose capture cannot be decoded has
        // no image for the fragment or a label to point at.
        let skipped = Set(report.skipped.map(\.file))
        let exported = files.filter { !skipped.contains($0) }
        let typ = target(name + ".typ")
        if options.typst {
            let text = TypstFragment.text(document, files: exported, format: options.format, typstImport: options.typstImport)
            try write(Data(text.utf8), to: typ, report: &report)
        } else {
            try remove(typ, if: TypstFragment.isOurs)
        }
        for kind in LabelsFile.Kind.allCases {
            let labels = target(name + "." + kind.fileExtension)
            if options.labels.includes(kind) {
                let text = LabelsFile.text(kind, document, files: exported, format: options.format)
                try write(Data(text.utf8), to: labels, report: &report)
            } else {
                try remove(labels) { LabelsFile.isOurs(kind, at: $0) }
            }
        }
        return kept
    }

    /// One step's file, without touching the rest of `notated/`.
    public static func exportStep(
        _ file: String,
        of document: CaseDocument,
        styles: Styles = .builtIn,
        folderName: String = ExportPlan.defaultFolder,
        options: ExportOptions = ExportOptions()
    ) throws(ExportError) -> ExportReport {
        let plan = try ExportPlan(document: document, folderName: folderName, format: options.format)
        try check(file, of: document)
        guard let target = plan.targets.first(where: { $0.file == file }) else {
            let reason = plan.skipped.first { $0.file == file }?.reason ?? "not exported"
            return ExportReport(skipped: [ExportPlan.Skipped(file: file, reason: reason)])
        }
        let data = try exportedData(for: file, of: document, styles: styles, options: options)
        var report = ExportReport(warnings: warnings(document, files: [file]))
        try write(data, to: target, report: &report)
        return report
    }

    /// The bytes the step's export file has, for the clipboard.
    public static func exportedData(
        for file: String,
        of document: CaseDocument,
        styles: Styles = .builtIn,
        options: ExportOptions = ExportOptions()
    ) throws(ExportError) -> Data {
        if let issue = document.sidecarIssue {
            throw .readOnly(issue)
        }
        try check(file, of: document)
        guard let data = render(file, of: document, styles: styles, numbers: document.counterNumbers, options: options) else {
            throw .unreadableImage(file)
        }
        return data
    }

    /// `exportedData` with the default options: a PNG at native size.
    public static func pngData(
        for file: String,
        of document: CaseDocument,
        styles: Styles = .builtIn
    ) throws(ExportError) -> Data {
        try exportedData(for: file, of: document, styles: styles)
    }

    private static func check(_ file: String, of document: CaseDocument) throws(ExportError) {
        guard let step = document.steps.first(where: { $0.file == file }) else {
            throw .unknownStep(file)
        }
        if step.excluded {
            throw .excluded(file)
        }
    }

    static func render(
        _ file: String,
        of document: CaseDocument,
        styles: Styles,
        numbers: [UUID: Int],
        options: ExportOptions = ExportOptions()
    ) -> Data? {
        guard let (scene, crop) = scene(file, of: document, styles: styles, numbers: numbers, options: options) else {
            return nil
        }
        var picture = Renderer.render(scene, crop: crop, scale: options.scale)
        let caption = document.caption(for: file)
        if options.captions, !caption.isEmpty {
            picture = Renderer.captioned(picture, caption: caption)
        }
        return options.encode(picture)
    }

    /// The step to draw as export draws it, with its crop; the contact sheet
    /// draws the same.
    static func scene(
        _ file: String,
        of document: CaseDocument,
        styles: Styles,
        numbers: [UUID: Int],
        options: ExportOptions
    ) -> (Scene, CGRect?)? {
        guard let step = document.steps.first(where: { $0.file == file }),
            let entry = document.sidecar.steps.first(where: { $0.file == file }),
            let image = Renderer.loadImage(at: step.url)
        else {
            return nil
        }
        let items = options.counters ? entry.items : entry.items.filter {
            if case .counter = $0.shape {
                return false
            }
            return true
        }
        let scene = Scene(
            image: image,
            items: items,
            numbers: numbers,
            transform: StepTransform(scale: step.scale),
            styles: styles
        )
        return (scene, entry.crop)
    }

    private static func write(
        _ data: Data,
        to target: ExportPlan.Target,
        report: inout ExportReport
    ) throws(ExportError) {
        if (try? Data(contentsOf: target.output)) == data {
            report.unchanged.append(target.relative)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: target.output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: target.output, options: .atomic)
        } catch {
            throw .writeFailed("\(target.relative): \(error.localizedDescription)")
        }
        report.written.append(target.relative)
    }

    /// `.png` files directly in the export folder and its `assets/` that
    /// this export did not produce, removed; sorted for the report.
    private static func removeStale(
        _ plan: ExportPlan,
        keeping kept: Set<String> = []
    ) throws(ExportError) -> [String] {
        let wanted = Set(plan.targets.map { $0.output.standardizedFileURL.path }).union(kept)
        let prefix = plan.folder.lastPathComponent
        var removed: [String] = []
        for (folder, relative) in [(plan.folder, prefix), (plan.folder.appendingPathComponent(CaseDocument.assetsFolder), prefix + "/" + CaseDocument.assetsFolder)] {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
                continue
            }
            for name in names where ["png", "jpg"].contains((name as NSString).pathExtension.lowercased()) {
                let url = folder.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                    !wanted.contains(url.standardizedFileURL.path)
                else {
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    throw .writeFailed("\(relative)/\(name): \(error.localizedDescription)")
                }
                removed.append(relative + "/" + name)
            }
        }
        return removed.sorted()
    }

    /// Items kept but not drawn, and steps exported unscaled because their
    /// size is not a multiple of the recorded one.
    private static func warnings(_ document: CaseDocument, files: [String]) -> [String] {
        let exported = Set(files)
        var warnings = document.sidecar.itemIssues.map { $0 + "; kept, not drawn" }
        for step in document.steps where exported.contains(step.file) {
            if case .mismatch(let recorded, let actual) = step.scale {
                warnings.append("\(step.file): recorded at \(recorded), image is \(actual); exported unscaled")
            }
        }
        return warnings
    }
}
