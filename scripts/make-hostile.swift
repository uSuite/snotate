// Writes the hostile fixture cases (SN-605) into the folder given as the
// first argument. Generated, not committed: the 8k capture and the 100-step
// case are large. Each case folder is named poc-hostile-<what>, its own
// case id, with captures named <case-id>-<nn>.<ext>.
//
// big: one 8192 x 8192 capture with an arrow in its sidecar.
// many: 100 steps of 1600 x 1000.
// unknown: a sidecar with keys sNotate does not know at every level.
// crlf, bom: memos with CRLF line endings and with a byte-order mark.
// broken: a good capture, a zero-byte one, text named .png and a truncated
// PNG.
// deep: 16-bit, Display P3, grey, alpha and CMYK captures.
// names: NFD Vietnamese, spaces and a symlinked capture.
// conflict: a sidecar with git conflict markers.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
try? fm.removeItem(at: root)
try! fm.createDirectory(at: root, withIntermediateDirectories: true)

func folder(_ name: String) -> URL {
    let url = root.appendingPathComponent("poc-hostile-\(name)", isDirectory: true)
    try! fm.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func capture(
    _ width: Int,
    _ height: Int,
    shade: Int,
    space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
    bits: Int = 8,
    alpha: Bool = false
) -> CGImage {
    // Grey and CMYK have no padding byte to skip.
    let padded = space.numberOfComponents == 3
    let info: UInt32 = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue
        : padded ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.none.rawValue
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: bits,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: info | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
    )!
    let base = CGFloat(shade % 200 + 30) / 255
    context.setFillColor(CGColor(srgbRed: base, green: 0.5, blue: 1 - base, alpha: alpha ? 0.6 : 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    for row in stride(from: 0, to: height, by: max(height / 10, 1)) {
        context.fill(CGRect(x: width / 10, y: row, width: width * 8 / 10, height: max(height / 40, 1)))
    }
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL, type: UTType = .png) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

func text(_ string: String, to url: URL) {
    try! Data(string.utf8).write(to: url)
}

func name(_ caseFolder: URL, _ number: Int, _ ext: String = "png") -> URL {
    caseFolder.appendingPathComponent("\(caseFolder.lastPathComponent)-\(String(format: "%02d", number)).\(ext)")
}

// 8192 x 8192, drawn in a grey context to keep the generator's memory down.
let big = folder("big")
let side = 8192
let grey = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceGray(),
    bitmapInfo: CGImageAlphaInfo.none.rawValue
)!
grey.setFillColor(gray: 0.85, alpha: 1)
grey.fill(CGRect(x: 0, y: 0, width: side, height: side))
grey.setFillColor(gray: 0.3, alpha: 1)
for row in stride(from: 0, to: side, by: 256) {
    grey.fill(CGRect(x: 512, y: row, width: side - 1024, height: 64))
}
write(grey.makeImage()!, to: name(big, 0))
text(
    """
    {
      "steps": [
        {
          "excluded": false,
          "file": "poc-hostile-big-00.png",
          "items": [
            {
              "from": [6000, 6000],
              "preset": 1,
              "to": [2000, 2000],
              "type": "arrow"
            }
          ],
          "size": [8192, 8192]
        }
      ]
    }

    """,
    to: big.appendingPathComponent("poc-hostile-big.snotate.json")
)

let many = folder("many")
for number in 0..<100 {
    write(capture(1600, 1000, shade: number), to: name(many, number))
}

let unknown = folder("unknown")
write(capture(400, 300, shade: 1), to: name(unknown, 0))
text(
    """
    {
      "future_top": {
        "nested": [1, 2, 3]
      },
      "steps": [
        {
          "excluded": false,
          "file": "poc-hostile-unknown-00.png",
          "future_step": "kept",
          "items": [
            {
              "at": [100, 100],
              "future_item": true,
              "preset": 1,
              "type": "counter"
            },
            {
              "at": [200, 100],
              "type": "sparkle"
            }
          ],
          "size": [400, 300]
        }
      ]
    }

    """,
    to: unknown.appendingPathComponent("poc-hostile-unknown.snotate.json")
)

for (kind, ending, prefix) in [("crlf", "\r\n", ""), ("bom", "\n", "\u{FEFF}")] {
    let memoCase = folder(kind)
    let id = memoCase.lastPathComponent
    var lines = ["# \(id)", ""]
    for number in 0..<3 {
        write(capture(400, 300, shade: number * 40), to: name(memoCase, number))
        let file = name(memoCase, number).lastPathComponent
        lines += ["- Step \(number) in a \(kind) memo", "", "![\(id)-\(String(format: "%02d", number))](\(file))", ""]
    }
    text(prefix + lines.joined(separator: ending), to: memoCase.appendingPathComponent("\(id).md"))
}

let broken = folder("broken")
write(capture(400, 300, shade: 2), to: name(broken, 0))
fm.createFile(atPath: name(broken, 1).path, contents: Data())
text("plain text pretending to be a PNG\n", to: name(broken, 2))
let whole = try! Data(contentsOf: name(broken, 0))
try! whole.prefix(whole.count / 3).write(to: name(broken, 3))

let deep = folder("deep")
write(capture(400, 300, shade: 3, bits: 16), to: name(deep, 0))
write(capture(400, 300, shade: 4, space: CGColorSpace(name: CGColorSpace.displayP3)!), to: name(deep, 1))
write(capture(400, 300, shade: 5, space: CGColorSpace(name: CGColorSpace.linearGray)!), to: name(deep, 2))
write(capture(400, 300, shade: 6, alpha: true), to: name(deep, 3))
write(
    capture(400, 300, shade: 7, space: CGColorSpace(name: CGColorSpace.genericCMYK)!),
    to: name(deep, 4, "jpg"),
    type: .jpeg
)

let names = folder("names")
let nfd = "bước chụp màn hình".decomposedStringWithCanonicalMapping
write(capture(400, 300, shade: 8), to: names.appendingPathComponent("\(nfd).png"))
write(capture(400, 300, shade: 9), to: names.appendingPathComponent("with spaces (1).png"))
write(capture(400, 300, shade: 10), to: name(names, 0))
try! fm.createSymbolicLink(
    at: names.appendingPathComponent("linked.png"),
    withDestinationURL: name(names, 0)
)

let conflict = folder("conflict")
write(capture(400, 300, shade: 11), to: name(conflict, 0))
text(
    """
    {
    <<<<<<< HEAD
      "steps": []
    =======
      "steps": [{"file": "poc-hostile-conflict-00.png", "items": []}]
    >>>>>>> other
    }

    """,
    to: conflict.appendingPathComponent("poc-hostile-conflict.snotate.json")
)

print("hostile fixtures in \(root.path)")
