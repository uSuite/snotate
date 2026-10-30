import Foundation
import ImageIO

/// SN-304: an image dropped or pasted into the case becomes a step at a
/// place in the story. It is copied into the case folder under a
/// provisional name, `snotate-YYYY-MM-DD-HHMMSS.png` (`-1`, `-2` for more
/// in the same second), the shape of `scap-` captures, so the
/// rename plan, or the evidence script, numbers it like any capture.
/// `.png`, `.jpg` and `.jpeg` files are copied byte for byte; other images
/// and pasted data are written as PNG. Never over an existing file.
public enum InsertStep {
    public enum Source: Sendable, Equatable {
        case file(URL)
        /// Encoded image data, such as the clipboard's.
        case data(Data)
    }

    public struct Failure: Error, Sendable, Equatable, CustomStringConvertible {
        public let description: String
    }

    static let copied: Set<String> = ["png", "jpg", "jpeg"]

    /// Writes each source into `folder` and returns the new file names in
    /// order; a source that is not an image is a failure before anything
    /// is written.
    public static func copy(
        _ sources: [Source],
        into folder: URL,
        date: Date = Date()
    ) throws(Failure) -> [String] {
        var prepared: [(data: Data, ext: String)] = []
        for source in sources {
            switch source {
            case .file(let url):
                let ext = url.pathExtension.lowercased()
                if copied.contains(ext), let data = try? Data(contentsOf: url), decodes(data) {
                    prepared.append((data, ext))
                } else if let data = try? Data(contentsOf: url), let png = png(from: data) {
                    prepared.append((png, "png"))
                } else {
                    throw Failure(description: "\(url.lastPathComponent) is not an image")
                }
            case .data(let data):
                guard let png = png(from: data) else {
                    throw Failure(description: "the pasted data is not an image")
                }
                prepared.append((png, "png"))
            }
        }
        var names: [String] = []
        for item in prepared {
            let name = freeName(in: folder, date: date, ext: item.ext, taken: Set(names))
            do {
                try item.data.write(to: folder.appendingPathComponent(name), options: .withoutOverwriting)
            } catch {
                throw Failure(description: "cannot write \(name): \(error.localizedDescription)")
            }
            names.append(name)
        }
        return names
    }

    /// The sidecar with an entry for each new file at `gap` among the
    /// steps (0 before the first, the step count after the last), so the
    /// next load keeps them where they were dropped.
    public static func placed(
        _ names: [String],
        at gap: Int,
        in document: CaseDocument
    ) -> Sidecar {
        var sidecar = document.sidecar
        let steps = document.steps.map(\.file)
        var index: Int
        if gap < steps.count, let anchor = sidecar.steps.firstIndex(where: { $0.file == steps[gap] }) {
            index = anchor
        } else if let last = steps.last, let anchor = sidecar.steps.firstIndex(where: { $0.file == last }) {
            index = anchor + 1
        } else {
            index = sidecar.steps.count
        }
        for name in names {
            let size = PixelSize(imageAt: document.folder.appendingPathComponent(name))
            sidecar.steps.insert(SidecarStep(file: name, size: size), at: index)
            index += 1
        }
        return sidecar
    }

    static func freeName(
        in folder: URL,
        date: Date,
        ext: String,
        taken: Set<String>
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stem = "snotate-" + formatter.string(from: date)
        var name = "\(stem).\(ext)"
        var n = 1
        while taken.contains(name) || FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(stem)-\(n).\(ext)"
            n += 1
        }
        return name
    }

    static func decodes(_ data: Data) -> Bool {
        CGImageSourceCreateWithData(data as CFData, nil).map { CGImageSourceGetCount($0) > 0 } ?? false
    }

    static func png(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return Renderer.pngData(image)
    }
}
