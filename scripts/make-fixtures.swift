// Generates the fixture cases under fixtures/: synthetic step captures and
// the case memo, in the evidence memo layout. No real customer
// data. Run with `make fixtures`; output is deterministic and committed.
//
// poc-sample-vm-migrate: six 1600 x 1000 steps, the everyday case.
// poc-sample-vm-scale: the same console at 1x, at 2x (an exact multiple,
// annotations scale) and at an odd size (not a multiple, the step is
// flagged), for the SN-102 scale rule.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let baseWidth = 1600
let baseHeight = 1000

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

/// Draws `string` with its baseline-left corner at `origin`, y up.
func label(
    _ string: String,
    at origin: CGPoint,
    size: CGFloat,
    hex: UInt32,
    in context: CGContext
) {
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
    let text = NSAttributedString(
        string: string,
        attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex),
        ]
    )
    context.textPosition = origin
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
}

/// A fake console page: title bar, sidebar, a row of list items and one
/// coloured panel per step, so annotations have edges to land on. The page
/// is drawn in base coordinates; another pixel size scales the same picture.
func capture(
    _ index: Int,
    panel: UInt32,
    title: String,
    width: Int = baseWidth,
    height: Int = baseHeight
) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    if width != baseWidth || height != baseHeight {
        context.scaleBy(
            x: CGFloat(width) / CGFloat(baseWidth),
            y: CGFloat(height) / CGFloat(baseHeight)
        )
    }
    let full = CGRect(x: 0, y: 0, width: baseWidth, height: baseHeight)
    context.setFillColor(color(0xf2f3f5))
    context.fill(full)
    context.setFillColor(color(0x1f2733))
    context.fill(CGRect(x: 0, y: baseHeight - 64, width: baseWidth, height: 64))
    label(
        "Console (synthetic)   10.0.0.10   admin",
        at: CGPoint(x: 24, y: baseHeight - 42),
        size: 22,
        hex: 0xd0d6e0,
        in: context
    )
    context.setFillColor(color(0xe1e4ea))
    context.fill(CGRect(x: 0, y: 0, width: 260, height: baseHeight - 64))
    for row in 0..<8 {
        let y = CGFloat(baseHeight - 130 - row * 56)
        context.setFillColor(color(row == index ? panel : 0xc4c9d2))
        context.fill(CGRect(x: 24, y: y, width: 212, height: 32))
    }
    let card = CGRect(x: 320, y: 120, width: 1220, height: 740)
    context.setFillColor(color(panel))
    context.fill(card)
    context.setStrokeColor(color(0xffffff))
    context.setLineWidth(6)
    context.stroke(card.insetBy(dx: 24, dy: 24))
    label(
        String(format: "Step %02d", index),
        at: CGPoint(x: card.minX + 72, y: card.maxY - 200),
        size: 120,
        hex: 0xffffff,
        in: context
    )
    label(
        title,
        at: CGPoint(x: card.minX + 72, y: card.maxY - 290),
        size: 40,
        hex: 0xffffff,
        in: context
    )
    for button in 0..<3 {
        let x = card.minX + 72 + CGFloat(button) * 260
        context.setFillColor(color(0xffffff, button == index % 3 ? 1 : 0.45))
        context.fill(CGRect(x: x, y: card.minY + 90, width: 220, height: 64))
    }
    return context.makeImage()!
}

func write(_ path: String, _ image: CGImage) {
    let url = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "cannot write \(path)")
}

struct Step {
    let panel: UInt32
    let title: String
    let caption: String
    var width = baseWidth
    var height = baseHeight
}

/// Writes one case folder: `<caseID>/<caseID>-NN.png` per step and the memo.
func writeCase(_ caseID: String, _ steps: [Step]) {
    var memo = "# \(caseID)\n"
    for (index, step) in steps.enumerated() {
        let file = String(format: "\(caseID)-%02d", index)
        write(
            "\(caseID)/\(file).png",
            capture(
                index,
                panel: step.panel,
                title: step.title,
                width: step.width,
                height: step.height
            )
        )
        memo += "\n- \(step.caption)\n\n![\(file)](\(file).png)\n"
    }
    try! Data(memo.utf8).write(to: root.appendingPathComponent("\(caseID)/\(caseID).md"))
}

writeCase(
    "poc-sample-vm-migrate",
    [
        Step(panel: 0x1e5eff, title: "VM list", caption: "Open the VM list and pick the running VM to migrate"),
        Step(panel: 0x7a4cc2, title: "Actions menu", caption: "Open **Actions** > **Migrate** on the VM"),
        Step(panel: 0x0e8a7a, title: "Target host", caption: "Choose the target host in the same cluster"),
        Step(panel: 0xd97a00, title: "Confirm", caption: "Confirm the migration in the dialog"),
        Step(panel: 0xc23b5a, title: "Task running", caption: "The task list shows the migration running"),
        Step(panel: 0x2f8a3a, title: "VM on new host", caption: "The VM is Running on the target host"),
    ]
)

writeCase(
    "poc-sample-vm-scale",
    [
        Step(panel: 0x1e5eff, title: "VM list at 1x", caption: "The console captured at 1x, 1600 x 1000"),
        Step(
            panel: 0x7a4cc2,
            title: "VM list at 2x",
            caption: "The same console captured at 2x, 3200 x 2000: an exact multiple, annotations scale",
            width: 3200,
            height: 2000
        ),
        Step(
            panel: 0x0e8a7a,
            title: "VM list, odd size",
            caption: "The same console at 1592 x 982: not a multiple, the step is flagged",
            width: 1592,
            height: 982
        ),
    ]
)
