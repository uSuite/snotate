import CoreGraphics
import Foundation

/// SN-506: the Settings window's preview of one preset, the way Terminal
/// shows a profile: a small console page drawn in code with an arrow, a
/// rectangle, two counters, text and a blurred hostname on it, rendered by
/// the one `Renderer`, so it is exactly what the canvas and export draw.
public enum PresetPreview {
    public static let width = 520
    public static let height = 300

    public static func render(_ style: Style) -> CGImage {
        let counters = [UUID(), UUID()]
        let items = [
            Annotation(shape: .blur(CGRect(x: 120, y: 102, width: 150, height: 18), pixelate: false)),
            Annotation(shape: .rectangle(CGRect(x: 352, y: 226, width: 120, height: 44), fill: false)),
            Annotation(shape: .arrow(from: CGPoint(x: 250, y: 218), to: CGPoint(x: 344, y: 246), curve: nil)),
            Annotation(id: counters[0], shape: .counter(at: CGPoint(x: 70, y: 110))),
            Annotation(id: counters[1], shape: .counter(at: CGPoint(x: 330, y: 194))),
            Annotation(shape: .text(at: CGPoint(x: 60, y: 196), text: "Then Save", pill: false, leader: nil)),
        ]
        let scene = Scene(
            image: sample,
            items: items,
            numbers: [counters[0]: 1, counters[1]: 2],
            styles: Styles(presets: [1: style])
        )
        return Renderer.render(scene)
    }

    /// A light console page: title bar, a table of rows with text-like
    /// bars, and a button, in neutral greys so any preset colour reads.
    static let sample: CGImage = {
        let context = Renderer.bitmap(width: width, height: height)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        func fill(_ rect: CGRect, _ grey: CGFloat) {
            context.setFillColor(CGColor(gray: grey, alpha: 1))
            context.fill(rect)
        }
        fill(CGRect(x: 0, y: 0, width: width, height: height), 0.93)
        fill(CGRect(x: 20, y: 20, width: width - 40, height: height - 40), 1)
        fill(CGRect(x: 20, y: 20, width: width - 40, height: 36), 0.86)
        for (index, x) in [36, 54, 72].enumerated() {
            context.setFillColor(CGColor(gray: 0.62 + 0.08 * CGFloat(index), alpha: 1))
            context.fillEllipse(in: CGRect(x: x, y: 32, width: 11, height: 11))
        }
        for row in 0..<3 {
            let y = CGFloat(76 + row * 34)
            fill(CGRect(x: 36, y: y + 33, width: CGFloat(width - 72), height: 1), 0.88)
            fill(CGRect(x: 96, y: y + 10, width: 14, height: 14), 0.8)
            fill(CGRect(x: 120, y: y + 12, width: CGFloat(150 - row * 20), height: 10), 0.55)
            fill(CGRect(x: 300, y: y + 12, width: CGFloat(110 + row * 12), height: 10), 0.72)
        }
        fill(CGRect(x: 362, y: 236, width: 100, height: 24), 0.45)
        fill(CGRect(x: 384, y: 245, width: 56, height: 6), 0.95)
        return context.makeImage()!
    }()
}
