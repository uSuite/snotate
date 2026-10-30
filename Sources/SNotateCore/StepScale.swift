import Foundation
import ImageIO

extension PixelSize {
    /// The stored pixel size from the image header, without decoding the
    /// image; `nil` when the file is missing or not an image. EXIF orientation
    /// is not applied: sidecar coordinates are in the file's own pixels.
    public init?(imageAt url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0,
            height > 0
        else {
            return nil
        }
        self.init(width: width, height: height)
    }
}

/// How a step's annotations, recorded at one pixel size, apply to the image
/// on disk (SN-102). Captures of a PoC share one window, so a different size
/// is either the same window at another backing scale, an exact multiple
/// whose annotations scale, or something else, which is flagged.
public enum StepScale: Sendable, Equatable {
    case match
    /// Multiply recorded coordinates by this factor.
    case scaled(Double)
    case mismatch(recorded: PixelSize, actual: PixelSize)

    public init(recorded: PixelSize, actual: PixelSize) {
        if recorded == actual {
            self = .match
        } else if let factor = Self.factor(actual, over: recorded) {
            self = .scaled(Double(factor))
        } else if let factor = Self.factor(recorded, over: actual) {
            self = .scaled(1 / Double(factor))
        } else {
            self = .mismatch(recorded: recorded, actual: actual)
        }
    }

    /// The whole number k with `large == small * k` on both sides.
    private static func factor(_ large: PixelSize, over small: PixelSize) -> Int? {
        guard large.width % small.width == 0, large.height % small.height == 0 else {
            return nil
        }
        let k = large.width / small.width
        return k > 1 && large.height / small.height == k ? k : nil
    }
}
