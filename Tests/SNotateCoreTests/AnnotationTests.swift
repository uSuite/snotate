import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct AnnotationTests {
    private func item(_ text: String) throws -> JSONValue {
        try JSONValue.parse(Data(text.utf8))
    }

    private func decode(_ text: String) throws -> Annotation {
        Annotation(json: try item(text), path: "items[0]")
    }

    @Test func everyToolDecodesToItsShape() throws {
        let cases: [(String, Shape)] = [
            (#"{"type": "arrow", "from": [600, 300], "to": [412, 240]}"#, .arrow(from: CGPoint(x: 600, y: 300), to: CGPoint(x: 412, y: 240), curve: nil)),
            (#"{"type": "arrow", "from": [0, 0], "to": [10, 0], "curve": [5, 5]}"#, .arrow(from: .zero, to: CGPoint(x: 10, y: 0), curve: CGPoint(x: 5, y: 5))),
            (#"{"type": "rectangle", "rect": [1, 2, 3, 4]}"#, .rectangle(CGRect(x: 1, y: 2, width: 3, height: 4), fill: false)),
            (#"{"type": "ellipse", "rect": [1, 2, 3, 4], "fill": true}"#, .ellipse(CGRect(x: 1, y: 2, width: 3, height: 4), fill: true)),
            (#"{"type": "counter", "at": [412, 230]}"#, .counter(at: CGPoint(x: 412, y: 230))),
            (#"{"type": "text", "at": [620, 310], "text": "Chọn VM cần dừng"}"#, .text(at: CGPoint(x: 620, y: 310), text: "Chọn VM cần dừng", pill: false, leader: nil)),
            (#"{"type": "text", "at": [0, 0], "text": "x", "pill": true, "leader": [9, 9]}"#, .text(at: .zero, text: "x", pill: true, leader: CGPoint(x: 9, y: 9))),
            (#"{"type": "highlight", "rect": [1, 2, 3, 4], "spotlight": true}"#, .highlight(CGRect(x: 1, y: 2, width: 3, height: 4), spotlight: true)),
            (#"{"type": "blur", "rect": [1500, 40, 240, 28]}"#, .blur(CGRect(x: 1500, y: 40, width: 240, height: 28), pixelate: false)),
            (#"{"type": "blur", "rect": [1, 2, 3, 4], "pixelate": true}"#, .blur(CGRect(x: 1, y: 2, width: 3, height: 4), pixelate: true)),
        ]
        for (text, shape) in cases {
            let annotation = try decode(text)
            #expect(annotation.shape == shape)
            #expect(annotation.preset == 1)
            #expect(annotation.json == (try item(text)).merging(preset: 1))
        }
    }

    @Test func presetAndUnknownKeysAreKept() throws {
        let annotation = try decode(#"{"type": "counter", "at": [1, 2], "n": 7, "preset": 3, "pulse": {"ms": 200}}"#)
        #expect(annotation.preset == 3)
        #expect(annotation.extra == ["n": .number(7), "pulse": .object(["ms": .number(200)])])
        #expect(annotation.json == (try item(#"{"type": "counter", "at": [1, 2], "n": 7, "preset": 3, "pulse": {"ms": 200}}"#)))
    }

    @Test func defaultFlagsAreNotWritten() throws {
        let annotation = Annotation(shape: .rectangle(CGRect(x: 1, y: 2, width: 3, height: 4), fill: false))
        #expect(annotation.json == (try item(#"{"type": "rectangle", "rect": [1, 2, 3, 4], "preset": 1}"#)))
    }

    @Test func unknownAndBrokenItemsAreKeptAsTheyWere() throws {
        let cases: [(String, String)] = [
            (#"{"type": "magnifier", "at": [1, 2], "zoom": 3}"#, "items[0]: unknown type 'magnifier'"),
            (#"{"type": "arrow", "from": [1, 2]}"#, "items[0].to is missing"),
            (#"{"type": "rectangle", "rect": [1, 2]}"#, "items[0].rect should be [x, y, width, height]"),
            (#"{"at": [1, 2]}"#, "items[0].type is missing"),
            (#"[1, 2]"#, "items[0] is not an object"),
            (#"{"type": "text", "at": [1, 2], "text": "x", "pill": "yes"}"#, "items[0].pill should be true or false"),
        ]
        for (text, reason) in cases {
            let annotation = try decode(text)
            #expect(annotation.shape == .unknown(try item(text), reason: reason))
            #expect(annotation.json == (try item(text)))
        }
    }

    @Test func equalityIgnoresTheInMemoryID() {
        let shape = Shape.counter(at: CGPoint(x: 1, y: 2))
        let a = Annotation(shape: shape)
        let b = Annotation(shape: shape)
        #expect(a.id != b.id)
        #expect(a == b)
        #expect(a != Annotation(shape: shape, preset: 2))
    }

    @Test func stepsTypeCropAndRestartCounterAndListItemIssues() throws {
        let text = """
            {"steps": [{"file": "a.png", "crop": [0, 88, 1920, 992], "restart_counter": true,
              "items": [{"type": "counter", "at": [1, 2]}, {"type": "laser"}]}]}
            """
        let sidecar = try Sidecar.decode(Data(text.utf8))
        let step = sidecar.steps[0]
        #expect(step.crop == CGRect(x: 0, y: 88, width: 1920, height: 992))
        #expect(step.restartCounter)
        #expect(step.extra.isEmpty)
        #expect(step.items.count == 2)
        #expect(sidecar.itemIssues == ["steps[0].items[1]: unknown type 'laser'"])
        let written = try Sidecar.decode(sidecar.encoded())
        #expect(written == sidecar)
        #expect(!String(decoding: Sidecar(steps: [SidecarStep(file: "b.png")]).encoded(), as: UTF8.self).contains("restart_counter"))
    }

    @Test func aBadCropMakesTheSidecarUnreadable() {
        #expect(throws: SidecarError.wrongType(key: "steps[0].crop", expected: "[x, y, width, height]")) {
            try Sidecar.decode(Data(#"{"steps": [{"file": "a.png", "crop": [1, 2]}]}"#.utf8))
        }
    }
}

extension JSONValue {
    /// This object with `preset` added, the form a written item takes.
    func merging(preset: Int) -> JSONValue {
        guard case .object(var object) = self else {
            return self
        }
        object["preset"] = object["preset"] ?? .number(Double(preset))
        return .object(object)
    }
}
