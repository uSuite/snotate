import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

/// Golden images in `fixtures/golden/`. `make golden` sets SNOTATE_GOLDEN=1
/// to write them; otherwise a render is compared with a tolerance (each
/// channel within 3, at most 0.5% of pixels off) so antialiasing changes
/// between macOS versions do not fail the build. A failure leaves the actual
/// render and a diff in `build/golden-diff/`.
enum Golden {
    static let folder = Fixtures.root.appendingPathComponent("golden", isDirectory: true)
    static let diffFolder = Fixtures.root
        .deletingLastPathComponent()
        .appendingPathComponent("build/golden-diff", isDirectory: true)
    static var writing: Bool { ProcessInfo.processInfo.environment["SNOTATE_GOLDEN"] == "1" }

    /// The second capture of the sample case, the canvas for every golden: its
    /// purple panel contrasts with all three preset colours.
    static let capture = Renderer.loadImage(at: Fixtures.url("poc-sample-vm-migrate/poc-sample-vm-migrate-01.png"))!

    static func check(
        _ image: CGImage,
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let url = folder.appendingPathComponent(name + ".png")
        if writing {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Renderer.pngData(image).write(to: url)
            return
        }
        guard let golden = Renderer.loadImage(at: url) else {
            Issue.record("no golden \(name).png; run make golden", sourceLocation: sourceLocation)
            return
        }
        guard golden.width == image.width, golden.height == image.height else {
            Issue.record("\(name): size \(image.width) x \(image.height), golden \(golden.width) x \(golden.height)", sourceLocation: sourceLocation)
            return
        }
        let actual = pixels(image)
        let expected = pixels(golden)
        var off = 0
        var diff = expected.map { $0 / 3 }
        for pixel in stride(from: 0, to: actual.count, by: 4) {
            let differs = (0..<4).contains { abs(Int(actual[pixel + $0]) - Int(expected[pixel + $0])) > 3 }
            if differs {
                off += 1
                diff[pixel] = 255
                diff[pixel + 1] = 0
                diff[pixel + 2] = 0
                diff[pixel + 3] = 255
            }
        }
        let limit = image.width * image.height / 200
        if off > limit {
            try FileManager.default.createDirectory(at: diffFolder, withIntermediateDirectories: true)
            try Renderer.pngData(image).write(to: diffFolder.appendingPathComponent(name + "-actual.png"))
            try Renderer.pngData(makeImage(diff, width: image.width, height: image.height))
                .write(to: diffFolder.appendingPathComponent(name + "-diff.png"))
            Issue.record("\(name): \(off) pixels differ (limit \(limit)); see build/golden-diff/", sourceLocation: sourceLocation)
        }
    }

    /// RGBA8 premultiplied sRGB bytes, top row first.
    static func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: Renderer.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    static func makeImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
        var copy = bytes
        return copy.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: Renderer.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!.makeImage()!
        }
    }

    /// The colour at an image pixel, top-left origin.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let bytes = pixels(image)
        let index = (y * image.width + x) * 4
        return Array(bytes[index..<index + 4])
    }
}
