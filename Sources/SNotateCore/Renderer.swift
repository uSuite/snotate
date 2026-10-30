import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One step to draw: the decoded capture, its annotations in stored pixels,
/// the counter numbers and the transform from stored to image pixels.
public struct Scene: Sendable {
    public var image: CGImage
    public var items: [Annotation]
    public var numbers: [UUID: Int]
    public var transform: StepTransform
    public var styles: Styles

    public init(
        image: CGImage,
        items: [Annotation],
        numbers: [UUID: Int] = [:],
        transform: StepTransform = StepTransform(scale: nil),
        styles: Styles = .builtIn
    ) {
        self.image = image
        self.items = items
        self.numbers = numbers
        self.transform = transform
        self.styles = styles
    }
}

/// The one renderer for screen and export (SN-603). `draw` paints into a
/// context already set up in image pixels, origin top-left and y down: the
/// canvas puts its view transform in front, `render` uses it as is. Style
/// sizes are stored pixels, so the whole annotation layer is scaled with
/// the step and a 2x step looks like its 1x original (DECISIONS 2026-10-26).
public enum Renderer {
    public static func draw(_ scene: Scene, in context: CGContext) {
        drawBase(scene, in: context)
        drawAnnotations(scene, in: context)
    }

    /// The capture with its blur and pixelate regions: what the canvas
    /// caches per step, since it changes only with a redaction.
    public static func drawBase(_ scene: Scene, in context: CGContext) {
        let size = CGSize(width: scene.image.width, height: scene.image.height)
        drawImage(scene.image, in: CGRect(origin: .zero, size: size), context: context)
        drawRedactions(scene, in: context)
    }

    /// `drawBase` as a bitmap at the image's own size.
    public static func base(_ scene: Scene) -> CGImage {
        let context = bitmap(width: scene.image.width, height: scene.image.height)
        context.translateBy(x: 0, y: CGFloat(scene.image.height))
        context.scaleBy(x: 1, y: -1)
        drawBase(scene, in: context)
        return context.makeImage()!
    }

    /// Every annotation but the redactions, over whatever is in `context`.
    public static func drawAnnotations(_ scene: Scene, in context: CGContext) {
        let size = CGSize(width: scene.image.width, height: scene.image.height)
        context.saveGState()
        context.scaleBy(x: scene.transform.factor, y: scene.transform.factor)
        let canvas = scene.transform.toStored(CGRect(origin: .zero, size: size))
        // All spotlights of a step are one dimming with a hole each, drawn
        // where the first one is in drawing order, so a second spotlight
        // does not darken the first one's area.
        let spotlights = scene.items.compactMap { item -> CGRect? in
            if case .highlight(let rect, true) = item.shape {
                return rect
            }
            return nil
        }
        var dimmed = false
        for item in scene.items {
            if case .highlight(_, true) = item.shape {
                if !dimmed {
                    drawSpotlight(spotlights, canvas: canvas, in: context)
                    dimmed = true
                }
                continue
            }
            let style = scene.styles.style(for: item.preset)
            context.saveGState()
            drawShape(item, style: style, numbers: scene.numbers, canvas: canvas, in: context)
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// The step at the image's own pixel size times `scale`, cropped to
    /// `crop` (stored pixels) when given: what export and the clipboard get.
    /// At scale 1 the drawing is exactly what it always was.
    public static func render(
        _ scene: Scene,
        crop: CGRect? = nil,
        scale: CGFloat = 1
    ) -> CGImage {
        let full = CGRect(x: 0, y: 0, width: scene.image.width, height: scene.image.height)
        let area = crop.map { scene.transform.toImage($0).integral.intersection(full) } ?? full
        let width = max(1, Int((area.width * scale).rounded()))
        let height = max(1, Int((area.height * scale).rounded()))
        let context = bitmap(width: width, height: height)
        if scale != 1 {
            context.interpolationQuality = .high
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.minX, y: -area.minY)
        draw(scene, in: context)
        return context.makeImage()!
    }

    /// `image` with `caption` burned in a white band under it (SN-403): the
    /// system font at 2.5% of the width, at least 14 pixels, wrapped and
    /// left-aligned; `**bold**` is drawn bold without its asterisks.
    public static func captioned(_ image: CGImage, caption: String) -> CGImage {
        let width = CGFloat(image.width)
        let size = max(14, (width * 0.025).rounded())
        let padding = (size * 0.8).rounded()
        let text = captionText(caption, size: size)
        let setter = CTFramesetterCreateWithAttributedString(text)
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
            setter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width - 2 * padding, height: .greatestFiniteMagnitude),
            nil
        )
        let band = fitted.height.rounded(.up) + 2 * padding
        let context = bitmap(width: image.width, height: image.height + Int(band))
        context.setFillColor(RGBA.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: band))
        context.draw(image, in: CGRect(x: 0, y: band, width: width, height: CGFloat(image.height)))
        let path = CGPath(rect: CGRect(x: padding, y: padding, width: width - 2 * padding, height: fitted.height.rounded(.up)), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
        return context.makeImage()!
    }

    /// The caption as styled text: runs between `**` pairs bold, an
    /// unpaired `**` kept as typed.
    static func captionText(
        _ caption: String,
        size: CGFloat,
        color: RGBA = RGBA(hex: 0x1F2328)
    ) -> NSAttributedString {
        let color = color.cgColor
        let parts = caption.components(separatedBy: "**")
        let paired = parts.count % 2 == 1
        let text = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            let bold = paired && index % 2 == 1
            let piece = paired || index == 0 ? part : "**" + part
            text.append(NSAttributedString(string: piece, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): TextLayout.font(size: size, bold: bold),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]))
        }
        return text
    }

    /// The step as `render` gives it, scaled to `width` pixels across: the
    /// storyboard's frames (SN-301). Drawn straight into the small bitmap,
    /// so shapes stay sharp and only the capture is resampled.
    public static func thumbnail(
        _ scene: Scene,
        crop: CGRect? = nil,
        width: Int
    ) -> CGImage {
        let full = CGRect(x: 0, y: 0, width: scene.image.width, height: scene.image.height)
        let area = crop.map { scene.transform.toImage($0).integral.intersection(full) } ?? full
        let scale = CGFloat(max(1, width)) / max(1, area.width)
        let height = max(1, Int((area.height * scale).rounded()))
        let context = bitmap(width: max(1, width), height: height)
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.minX, y: -area.minY)
        draw(scene, in: context)
        return context.makeImage()!
    }

    /// PNG bytes with fixed settings and no metadata, so the same picture
    /// always gives the same file.
    public static func pngData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The capture decoded once, in full.
    public static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        )
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func bitmap(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: max(1, width),
            height: max(1, height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// Core Image on the CPU, so blur and pixelate give the same pixels on
    /// any GPU (DECISIONS 2026-10-26).
    static let imageContext = CIContext(options: [
        .useSoftwareRenderer: true,
        .workingColorSpace: sRGB,
        .outputColorSpace: sRGB,
        .cacheIntermediates: false,
    ])

    /// Blur and pixelate regions, filtered from the bare capture and drawn
    /// before every other annotation whatever their place in drawing order:
    /// they hide things, so nothing drawn is ever blurred by accident and a
    /// counter on a hidden hostname stays crisp. The region's edges are
    /// clamped before filtering so the blur does not pull in transparency.
    static func drawRedactions(_ scene: Scene, in context: CGContext) {
        let width = CGFloat(scene.image.width)
        let height = CGFloat(scene.image.height)
        let source = CIImage(cgImage: scene.image)
        for item in scene.items {
            guard case .blur(let rect, let pixelate) = item.shape else {
                continue
            }
            let region = scene.transform.toImage(rect).integral
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard !region.isNull, !region.isEmpty else {
                continue
            }
            let radius = scene.styles.style(for: item.preset).blurRadius * scene.transform.factor
            let strength = redactionStrength(region.size, radius: radius, pixelate: pixelate)
            // Core Image is y up.
            let ciRegion = CGRect(x: region.minX, y: height - region.maxY, width: region.width, height: region.height)
            let clamped = source.cropped(to: ciRegion).clampedToExtent()
            let filtered: CIImage
            if pixelate {
                filtered = clamped.applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: strength,
                    kCIInputCenterKey: CIVector(x: ciRegion.minX, y: ciRegion.maxY),
                ])
            } else {
                filtered = clamped.applyingGaussianBlur(sigma: strength)
            }
            guard let output = imageContext.createCGImage(filtered.cropped(to: ciRegion), from: ciRegion) else {
                continue
            }
            drawImage(output, in: region, context: context)
        }
    }

    /// Pixelate block size or blur sigma for a region, in image pixels: the
    /// preset's radius, or more for a tall region, so text of any size under
    /// it is unreadable (blocks a quarter, blur a fifth of the shorter side).
    /// Console-size fields keep the preset's radius.
    static func redactionStrength(_ size: CGSize, radius: CGFloat, pixelate: Bool) -> CGFloat {
        let shorter = min(size.width, size.height)
        return pixelate ? max(2, radius, shorter / 4) : max(radius, shorter / 5)
    }

    /// `CGContext.draw` assumes y up; public so the canvas draws a cached
    /// base the same way. in our y-down space the image is
    /// flipped back around its own rectangle.
    /// `image` at `factor` of its size (1 or less) in 32-bit BGRA, the
    /// layout Core Graphics draws without converting, for the canvas only
    /// (SN-606): replaying a drawing converted and resampled the whole
    /// capture each time, so a large one cost several frames. Export never
    /// uses it.
    public static func displayCopy(of image: CGImage, factor: CGFloat) -> CGImage {
        let width = max(1, Int((CGFloat(image.width) * factor).rounded(.up)))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded(.up)))
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    public static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// One annotation in stored pixels; `canvas` is the whole image in the
    /// same units, for the spotlight.
    static func drawShape(
        _ item: Annotation,
        style: Style,
        numbers: [UUID: Int],
        canvas: CGRect,
        in context: CGContext
    ) {
        let color = style.color
        context.setLineWidth(style.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        switch item.shape {
        case .arrow(let from, let to, let curve):
            drawArrow(from: from, to: to, curve: curve, style: style, in: context)
        case .rectangle(let rect, let fill):
            let radius = min(style.strokeWidth, rect.width / 2, rect.height / 2)
            outline(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), fill: fill, color: color, in: context)
        case .ellipse(let rect, let fill):
            outline(CGPath(ellipseIn: rect, transform: nil), fill: fill, color: color, in: context)
        case .highlight(let rect, false):
            // A marker: the colour multiplies into the capture.
            context.setBlendMode(.multiply)
            context.setFillColor(color.with(alpha: 0.25).cgColor)
            context.fill(rect)
        case .highlight(let rect, true):
            drawSpotlight([rect], canvas: canvas, in: context)
        case .counter(let at):
            drawCounter(at: at, number: numbers[item.id], style: style, in: context)
        case .text(let at, let text, let pill, let leader):
            drawText(at: at, text: text, pill: pill, leader: leader, style: style, in: context)
        case .blur, .unknown:
            break
        }
    }

    /// A filled circle with a white bold number centred on its glyphs. A
    /// counter without a number (on an excluded step) is the circle alone.
    static func drawCounter(
        at centre: CGPoint,
        number: Int?,
        style: Style,
        in context: CGContext
    ) {
        let r = style.counterRadius
        context.fillEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        guard let number else {
            return
        }
        let line = TextLayout.line(
            String(number),
            font: TextLayout.font(size: r * 1.1, bold: true),
            color: RGBA.white.cgColor
        )
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        drawLine(line, at: CGPoint(x: centre.x - glyphs.midX, y: centre.y + glyphs.midY), in: context)
    }

    /// Text in the preset colour, or white on a pill of it. A leader runs
    /// from the box's nearest edge to its point, ending in a dot, and is
    /// drawn first so the pill covers its start.
    static func drawText(
        at origin: CGPoint,
        text: String,
        pill: Bool,
        leader: CGPoint?,
        style: Style,
        in context: CGContext
    ) {
        let layout = TextLayout(text: text, fontSize: style.fontSize)
        var box = CGRect(origin: origin, size: layout.size)
        if pill {
            let padding = Geometry.pillPadding(style)
            box = box.insetBy(dx: -padding, dy: -padding)
        }
        if let leader {
            let start = CGPoint(
                x: min(max(leader.x, box.minX), box.maxX),
                y: min(max(leader.y, box.minY), box.maxY)
            )
            context.setLineWidth(style.strokeWidth / 2)
            context.move(to: start)
            context.addLine(to: leader)
            context.strokePath()
            let dot = style.strokeWidth
            context.fillEllipse(in: CGRect(x: leader.x - dot, y: leader.y - dot, width: 2 * dot, height: 2 * dot))
        }
        if pill {
            let radius = min(box.height / 2, style.fontSize * 0.6)
            context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        let font = TextLayout.font(size: style.fontSize)
        let color = pill ? RGBA.white.cgColor : style.color.cgColor
        for (index, text) in layout.lines.enumerated() {
            let baseline = origin.y + CGFloat(index) * layout.lineHeight + layout.ascent
            drawLine(TextLayout.line(text, font: font, color: color), at: CGPoint(x: origin.x, y: baseline), in: context)
        }
    }

    /// Core Text draws y up; the line is flipped around its baseline point.
    static func drawLine(_ line: CTLine, at baseline: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: baseline.x, y: baseline.y)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Black at 45% over `canvas` except the union of `holes`; overlapping
    /// holes stay bright, which an even-odd fill would not do.
    static func drawSpotlight(_ holes: [CGRect], canvas: CGRect, in context: CGContext) {
        let open = holes.reduce(CGMutablePath()) { path, rect in
            path.addRect(rect)
            return path
        }
        context.addPath(CGPath(rect: canvas, transform: nil).subtracting(open, using: .winding))
        context.setFillColor(RGBA.black.with(alpha: 0.45).cgColor)
        context.fillPath()
    }

    /// A line ending at the base of a filled head whose tip is `to`; the
    /// head is 4 strokes long and 4 wide, inside `Geometry.arrowHeadReach`.
    /// A curved arrow's head follows the curve's direction at the end.
    static func drawArrow(
        from: CGPoint,
        to: CGPoint,
        curve: CGPoint?,
        style: Style,
        in context: CGContext
    ) {
        let tail = curve ?? from
        let dx = to.x - tail.x
        let dy = to.y - tail.y
        let length = hypot(dx, dy)
        guard length > 0 else {
            return
        }
        let ux = dx / length
        let uy = dy / length
        let headLength = min(style.strokeWidth * 4, length)
        let halfWidth = style.strokeWidth * 2
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        context.move(to: from)
        if let curve {
            context.addQuadCurve(to: base, control: curve)
        } else {
            context.addLine(to: base)
        }
        context.strokePath()
        context.move(to: to)
        context.addLine(to: CGPoint(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth))
        context.addLine(to: CGPoint(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth))
        context.closePath()
        context.fillPath()
    }

    /// Stroke, over a soft fill of the same colour when `fill` is set.
    static func outline(
        _ path: CGPath,
        fill: Bool,
        color: RGBA,
        in context: CGContext
    ) {
        if fill {
            context.addPath(path)
            context.setFillColor(color.with(alpha: 0.15).cgColor)
            context.fillPath()
        }
        context.addPath(path)
        context.strokePath()
    }
}
