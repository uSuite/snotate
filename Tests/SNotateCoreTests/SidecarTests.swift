import CoreGraphics
import Foundation
import Testing
@testable import SNotateCore

struct SidecarTests {
    /// The tech-stack example plus keys a newer sNotate might write, already in
    /// the canonical layout, so decoding and encoding must give it back as is.
    static let canonical = """
        {
          "counter": "continue",
          "future": {
            "camera": "ease"
          },
          "steps": [
            {
              "crop": [0, 88, 1920, 992],
              "excluded": false,
              "file": "poc-demo-vm-stop-00.png",
              "items": [
                {
                  "at": [412, 230],
                  "n": 1,
                  "preset": 1,
                  "pulse": true,
                  "type": "counter"
                },
                {
                  "at": [620, 310],
                  "preset": 2,
                  "text": "Chọn VM cần dừng",
                  "type": "text"
                }
              ],
              "size": [1518, 892],
              "timing": 1.5
            },
            {
              "caption": "No memo yet",
              "excluded": true,
              "file": "assets/scap-2026-10-22-160218.png",
              "items": [],
              "size": [3036, 1784]
            }
          ],
          "version": 1
        }

        """

    @Test func decodesKnownKeysAndKeepsTheRest() throws {
        let sidecar = try Sidecar.decode(Data(Self.canonical.utf8))
        #expect(sidecar.version == 1)
        #expect(sidecar.counter == "continue")
        #expect(sidecar.extra == ["future": .object(["camera": .string("ease")])])
        #expect(sidecar.steps.map(\.file) == ["poc-demo-vm-stop-00.png", "assets/scap-2026-10-22-160218.png"])
        let first = sidecar.steps[0]
        #expect(first.size == PixelSize(width: 1518, height: 892))
        #expect(first.excluded == false)
        #expect(first.caption == nil)
        #expect(first.items.count == 2)
        #expect(first.crop == CGRect(x: 0, y: 88, width: 1920, height: 992))
        #expect(first.extra == ["timing": .number(1.5)])
        #expect(first.items[0].extra == ["n": .number(1), "pulse": .bool(true)])
        #expect(sidecar.steps[1].excluded)
        #expect(sidecar.steps[1].caption == "No memo yet")
    }

    @Test func encodingGivesBackTheSameBytes() throws {
        let data = Data(Self.canonical.utf8)
        #expect(try Sidecar.decode(data).encoded() == data)
    }

    @Test func aMissingSizeIsAllowedAndOmitted() throws {
        let sidecar = try Sidecar.decode(Data(#"{"steps": [{"file": "a.png"}]}"#.utf8))
        #expect(sidecar.version == Sidecar.currentVersion)
        #expect(sidecar.steps[0].size == nil)
        #expect(sidecar.steps[0].items.isEmpty)
        #expect(String(decoding: sidecar.encoded(), as: UTF8.self) == """
            {
              "steps": [
                {
                  "excluded": false,
                  "file": "a.png",
                  "items": []
                }
              ],
              "version": 1
            }

            """)
    }

    @Test func anEmptySidecarIsStepsAndVersion() {
        #expect(String(decoding: Sidecar().encoded(), as: UTF8.self) == "{\n  \"steps\": [],\n  \"version\": 1\n}\n")
    }

    @Test func badShapesAreReportedByKey() {
        let cases: [(String, SidecarError)] = [
            ("[1]", .notAnObject("sidecar")),
            (#"{"steps": {}}"#, .wrongType(key: "steps", expected: "an array")),
            (#"{"version": "1", "steps": []}"#, .wrongType(key: "version", expected: "a whole number")),
            (#"{"steps": [3]}"#, .notAnObject("steps[0]")),
            (#"{"steps": [{"size": [1, 2]}]}"#, .missingKey("steps[0].file")),
            (#"{"steps": [{"file": "a.png", "size": [1]}]}"#, .wrongType(key: "steps[0].size", expected: "[width, height] in whole pixels")),
            (#"{"steps": [{"file": "a.png", "size": [1.5, 2]}]}"#, .wrongType(key: "steps[0].size", expected: "[width, height] in whole pixels")),
            (#"{"steps": [{"file": "a.png", "excluded": 0}]}"#, .wrongType(key: "steps[0].excluded", expected: "true or false")),
            (#"{"steps": [{"file": "a.png", "items": {}}]}"#, .wrongType(key: "steps[0].items", expected: "an array")),
        ]
        for (text, expected) in cases {
            #expect(throws: expected) {
                try Sidecar.decode(Data(text.utf8))
            }
        }
    }

    @Test func invalidJSONIsReported() {
        #expect {
            try Sidecar.decode(Data("<<<<<<< HEAD\n".utf8))
        } throws: { error in
            guard case SidecarError.invalidJSON = error else {
                return false
            }
            return true
        }
    }
}
