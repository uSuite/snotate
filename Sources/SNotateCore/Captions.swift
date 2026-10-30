import Foundation

/// Where a step's caption lives (SN-302): the memo is the report draft, so
/// a caption is its bullet whenever the memo references the image; the
/// sidecar holds it only while there is no memo or the memo does not
/// mention that image (DECISIONS 2026-10-25, 2026-10-27).
public enum CaptionSource: Sendable, Equatable {
    case memo
    case sidecar
    /// A memo exists but cannot be read; its reason.
    case readOnly(String)
}

extension CaseDocument {
    /// The caption for `file`: the memo bullet when the memo references
    /// it, the sidecar's otherwise; the evidence script's placeholder is
    /// no caption.
    public func caption(for file: String) -> String {
        if let entry = memo?.entry(for: file) {
            return entry.isPlaceholder ? "" : entry.caption ?? ""
        }
        return sidecar.steps.first { $0.file == file }?.caption ?? ""
    }
}

extension EditorState {
    public func captionSource(for file: String) -> CaptionSource {
        if document.memoURL != nil, let issue = document.memoIssue {
            return .readOnly(issue.description)
        }
        if document.memo?.entry(for: file) != nil {
            return .memo
        }
        return .sidecar
    }

    /// The caption shown for `file`; the evidence script's placeholder
    /// shows as empty.
    public func caption(for file: String) -> String {
        document.caption(for: file)
    }
}

/// Captions written while there was no memo move into it once it exists
/// and references their images: only where the memo has no caption of its
/// own (no bullet, or the placeholder), and the sidecar copy is then
/// removed. Where the memo already says something else, the memo wins and
/// the sidecar caption stays in the file, unused, so nothing is lost.
public enum CaptionMigration {
    public struct Result: Sendable, Equatable {
        public let memo: Memo
        public let sidecar: Sidecar
        /// Steps whose sidecar caption was kept because the memo differs.
        public let kept: [String]
    }

    /// `nil` when there is nothing to move and nothing to report.
    public static func migrate(memo: Memo, sidecar: Sidecar) -> Result? {
        var memo = memo
        var sidecar = sidecar
        var kept: [String] = []
        var changed = false
        for index in sidecar.steps.indices {
            let step = sidecar.steps[index]
            guard let caption = step.caption, let entry = memo.entry(for: step.file) else {
                continue
            }
            let own = entry.isPlaceholder ? nil : entry.caption.flatMap { $0.isEmpty ? nil : $0 }
            if let own, own != caption {
                kept.append(step.file)
                continue
            }
            if own == nil {
                guard let data = try? memo.settingCaption(caption, for: step.file), let updated = try? Memo(data: data) else {
                    kept.append(step.file)
                    continue
                }
                memo = updated
            }
            sidecar.steps[index].caption = nil
            changed = true
        }
        guard changed || !kept.isEmpty else {
            return nil
        }
        return Result(memo: memo, sidecar: sidecar, kept: kept)
    }
}
