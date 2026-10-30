import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How export renders and encodes (SN-403), from the config rather than a
/// dialog. The defaults are what export always did, so goldens and existing
/// `notated/` folders stay byte-identical (DECISIONS 2026-10-27).
public struct ExportOptions: Sendable, Equatable {
    public enum Format: String, Sendable, CaseIterable {
        case png
        case jpeg

        /// The extension of the exported file.
        public var fileExtension: String {
            self == .png ? "png" : "jpg"
        }
    }

    /// Times the step's native pixel size: 0.5, 1 or 2.
    public var scale: CGFloat = 1
    public var format = Format.png
    /// 1 to 100.
    public var jpegQuality = 90
    public var counters = true
    /// The caption burned in a band under the image.
    public var captions = false

    /// The case's contact sheet (SN-404).
    public enum Sheet: String, Sendable, CaseIterable {
        case off
        case png
        case pdf
        case both
    }

    public var sheet = Sheet.off
    /// `notated/<case-id>.typ`, the Typst fragment (SN-404), and the Typst
    /// package it imports `shot` from, `nil` for its own plain `figure`.
    public var typst = false
    public var typstImport: String?

    /// The steps' labels as `notated/<case-id>.md` and `.yaml` (SN-407).
    public enum Labels: String, Sendable, CaseIterable {
        case off
        case md
        case yaml
        case both

        public func includes(_ kind: LabelsFile.Kind) -> Bool {
            self == .both || rawValue == kind.rawValue
        }
    }

    public var labels = Labels.both

    public init() {}

    public init(config: SNotateConfig) {
        scale = config.exportScale
        format = config.exportFormat
        jpegQuality = config.jpegQuality
        counters = config.exportCounters
        captions = config.exportCaptions
        sheet = config.exportSheet
        typst = config.exportTypst
        typstImport = config.typstImport
        labels = config.exportLabels
    }

    public static let scales: [CGFloat] = [0.5, 1, 2]

    /// The bytes of `image` in this format, with fixed settings and no
    /// metadata, so the same picture always gives the same file.
    public func encode(_ image: CGImage) -> Data {
        guard format == .jpeg else {
            return Renderer.pngData(image)
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties = [kCGImageDestinationLossyCompressionQuality: CGFloat(jpegQuality) / 100] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
