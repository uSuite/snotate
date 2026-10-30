import CoreGraphics
import CoreText
import Foundation

/// SN-404: the exported steps of a case on one page, three to a row, each
/// with its number, file name and caption under it, the case id as the
/// title. The PNG is drawn from thumbnails; the PDF from the full renders,
/// so it stays sharp when zoomed, with vector text. Core Graphics stamps a
/// creation date into every PDF, so the PDF carries a hash of the sheet's
/// picture in its keywords and is rewritten only when that changes
/// (DECISIONS 2026-10-27).
public enum ContactSheet {
    static let columns = 3
    static let frameWidth: CGFloat = 800
    static let gap: CGFloat = 40
    static let margin: CGFloat = 60
    static let titleHeight: CGFloat = 70
    static let textHeight: CGFloat = 136

    struct Frame {
        let number: Int
        let file: String
        let caption: String
        let image: CGImage
    }

    /// The PNG, and the fingerprint the PDF records.
    public static func png(
        _ document: CaseDocument,
        files: [String],
        styles: Styles,
        options: ExportOptions
    ) -> (data: Data, fingerprint: String)? {
        let frames = frames(document, files: files, styles: styles, options: options, full: false)
        guard !frames.isEmpty else {
            return nil
        }
        let (size, rects) = layout(frames)
        let context = Renderer.bitmap(width: Int(size.width), height: Int(size.height))
        context.interpolationQuality = .high
        draw(frames, rects: rects, size: size, title: document.caseID, in: context)
        let data = Renderer.pngData(context.makeImage()!)
        return (data, fingerprint(data))
    }

    public static func pdf(
        _ document: CaseDocument,
        files: [String],
        styles: Styles,
        options: ExportOptions,
        fingerprint: String
    ) -> Data? {
        let frames = frames(document, files: files, styles: styles, options: options, full: true)
        guard !frames.isEmpty else {
            return nil
        }
        let (size, rects) = layout(frames)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let info = [
            kCGPDFContextCreator: "sNotate",
            kCGPDFContextTitle: document.caseID,
            kCGPDFContextKeywords: marker + fingerprint,
        ] as CFDictionary
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, info) else {
            return nil
        }
        context.beginPDFPage(nil)
        context.setFillColor(RGBA.white.cgColor)
        context.fill(box)
        draw(frames, rects: rects, size: size, title: document.caseID, in: context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    static let marker = "snotate-sheet "

    /// The fingerprint an existing PDF recorded, `nil` when it is not ours.
    static func recordedFingerprint(at url: URL) -> String? {
        guard let document = CGPDFDocument(url as CFURL), let info = document.info else {
            return nil
        }
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(info, "Keywords", &value), let value,
            let text = CGPDFStringCopyTextString(value) as String?, text.hasPrefix(marker)
        else {
            return nil
        }
        return String(text.dropFirst(marker.count))
    }

    /// FNV-1a over the bytes, as hex: enough to tell one picture from
    /// another, with nothing outside Foundation.
    static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    private static func frames(
        _ document: CaseDocument,
        files: [String],
        styles: Styles,
        options: ExportOptions,
        full: Bool
    ) -> [Frame] {
        let numbers = document.counterNumbers
        return files.enumerated().compactMap { index, file in
            guard let (scene, crop) = Exporter.scene(file, of: document, styles: styles, numbers: numbers, options: options) else {
                return nil
            }
            let image = full
                ? Renderer.render(scene, crop: crop)
                : Renderer.thumbnail(scene, crop: crop, width: Int(frameWidth))
            return Frame(number: index + 1, file: file, caption: document.caption(for: file), image: image)
        }
    }

    /// The page size and each frame's picture box, y down from the top.
    private static func layout(_ frames: [Frame]) -> (CGSize, [CGRect]) {
        var rects: [CGRect] = []
        var y = margin + titleHeight
        for row in stride(from: 0, to: frames.count, by: columns) {
            let rowFrames = frames[row..<min(row + columns, frames.count)]
            let heights = rowFrames.map { frameWidth * CGFloat($0.image.height) / CGFloat(max(1, $0.image.width)) }
            for (column, height) in heights.enumerated() {
                rects.append(CGRect(x: margin + CGFloat(column) * (frameWidth + gap), y: y, width: frameWidth, height: height.rounded()))
            }
            y += (heights.max() ?? 0).rounded() + textHeight + gap
        }
        let width = 2 * margin + CGFloat(columns) * frameWidth + CGFloat(columns - 1) * gap
        return (CGSize(width: width, height: y - gap + margin), rects)
    }

    /// Draws into a y-up context of `size`, converting the y-down layout.
    private static func draw(
        _ frames: [Frame],
        rects: [CGRect],
        size: CGSize,
        title: String,
        in context: CGContext
    ) {
        func up(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
        }
        context.setFillColor(RGBA.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        text(title, size: 40, bold: true, color: RGBA(hex: 0x1F2328), in: up(CGRect(x: margin, y: margin, width: size.width - 2 * margin, height: 56)), context: context)
        for (frame, rect) in zip(frames, rects) {
            context.draw(frame.image, in: up(rect))
            context.setStrokeColor(RGBA(hex: 0xD0D7DE).cgColor)
            context.setLineWidth(1)
            context.stroke(up(rect).insetBy(dx: 0.5, dy: 0.5))
            let label = CGRect(x: rect.minX, y: rect.maxY + 10, width: rect.width, height: 28)
            text("\(frame.number)  \(frame.file)", size: 20, bold: false, color: RGBA(hex: 0x57606A), in: up(label), context: context)
            let caption = CGRect(x: rect.minX, y: label.maxY + 4, width: rect.width, height: textHeight - 46)
            text(frame.caption, size: 24, bold: false, color: RGBA(hex: 0x1F2328), in: up(caption), context: context)
        }
    }

    /// Wrapped text in `rect`, `**bold**` honoured; what does not fit is cut.
    private static func text(
        _ string: String,
        size: CGFloat,
        bold: Bool,
        color: RGBA,
        in rect: CGRect,
        context: CGContext
    ) {
        let attributed = bold
            ? NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): TextLayout.font(size: size, bold: true),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
            ])
            : Renderer.captionText(string, size: size, color: color)
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil), context)
    }
}
