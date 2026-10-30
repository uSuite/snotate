// Renders the sNotate app icon from the brand SVG layers (brand/s.svg,
// brand/snotate-background.svg, brand/snotate-accent.svg; see sView's docs/04-branding.md)
// at every size an .icns needs, writing the iconset to the folder given as
// the first argument and a flat 1024 PNG to the second. `make icon` packs
// the iconset into Resources/AppIcon.icns. The SVGs are the only source.
import AppKit

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
let flat = URL(fileURLWithPath: CommandLine.arguments[2])
let layers = ["brand/snotate-background.svg", "brand/s.svg", "brand/snotate-accent.svg"].map { path -> NSImage in
    guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)) else {
        fatalError("cannot read \(path)")
    }
    return image
}

/// The layers inside the classic macOS tile (an 824 rounded square on a
/// 1024 canvas with a soft shadow), since a flat .icns has no glass.
func render(_ size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(CGColor(srgbRed: 0.85, green: 0.48, blue: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.addPath(shape)
    context.clip()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for layer in layers {
        layer.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.current = nil
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        write(render(base * scale), to: iconset.appendingPathComponent(name))
    }
}
write(render(1024), to: flat)
print("iconset written to \(iconset.path), flat icon to \(flat.path)")
