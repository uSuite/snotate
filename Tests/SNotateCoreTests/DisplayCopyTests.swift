import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

/// SN-606: the canvas draws a copy of the base in the layout Core Graphics
/// replays without converting, shrunk by a power of two; the pixels must be
/// the base's.
struct DisplayCopyTests {
    private func solid(_ width: Int, _ height: Int, space: CGColorSpace) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: space.model == .rgb ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The middle pixel as sRGB bytes, read back through a plain bitmap.
    private func middle(_ image: CGImage) -> [UInt8] {
        let context = Renderer.bitmap(width: 1, height: 1)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return [bytes[0], bytes[1], bytes[2], bytes[3]]
    }

    @Test func aCopyIsShrunkInTheNativeLayoutWithTheSamePixels() {
        let base = solid(1600, 1000, space: Renderer.sRGB)
        let copy = Renderer.displayCopy(of: base, factor: 0.25)
        #expect(copy.width == 400)
        #expect(copy.height == 250)
        #expect(copy.bitsPerPixel == 32)
        #expect(copy.alphaInfo == .premultipliedFirst)
        #expect(copy.bitmapInfo.contains(.byteOrder32Little))
        #expect(middle(copy) == middle(base))
    }

    @Test func oddSizesRoundUpAndAFactorOfOneKeepsTheSize() {
        let base = solid(801, 3, space: Renderer.sRGB)
        let half = Renderer.displayCopy(of: base, factor: 0.5)
        #expect(half.width == 401)
        #expect(half.height == 2)
        let same = Renderer.displayCopy(of: base, factor: 1)
        #expect(same.width == 801)
        #expect(same.height == 3)
    }

    @Test func wideGamutKeepsItsSpaceAndGreyBecomesSRGB() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        #expect(Renderer.displayCopy(of: solid(40, 40, space: p3), factor: 1).colorSpace?.name == CGColorSpace.displayP3)
        let grey = solid(40, 40, space: CGColorSpaceCreateDeviceGray())
        #expect(Renderer.displayCopy(of: grey, factor: 1).colorSpace?.name == CGColorSpace.sRGB)
    }
}
