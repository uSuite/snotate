import Foundation
import Testing
@testable import SNotateCore

struct JSONValueTests {
    @Test func parsesEveryKindAndKeepsBoolsApartFromNumbers() throws {
        let value = try JSONValue.parse(Data(#"{"a": true, "b": 1, "c": 1.5, "d": "x", "e": null, "f": [false, 0], "g": {}}"#.utf8))
        #expect(value == .object([
            "a": .bool(true),
            "b": .number(1),
            "c": .number(1.5),
            "d": .string("x"),
            "e": .null,
            "f": .array([.bool(false), .number(0)]),
            "g": .object([:]),
        ]))
    }

    @Test func invalidJSONThrows() {
        #expect(throws: (any Error).self) {
            try JSONValue.parse(Data("<<<<<<< HEAD\n{}\n".utf8))
        }
    }
}

struct SidecarWriterTests {
    private func text(_ value: JSONValue) -> String {
        String(decoding: SidecarWriter.data(value), as: UTF8.self)
    }

    @Test func objectsAreSortedIndentedByTwoWithNoSpaceBeforeTheColon() {
        let value: JSONValue = .object([
            "version": .number(1),
            "steps": .array([
                .object([
                    "file": .string("a.png"),
                    "excluded": .bool(false),
                ])
            ]),
            "counter": .string("continue"),
        ])
        #expect(text(value) == """
            {
              "counter": "continue",
              "steps": [
                {
                  "excluded": false,
                  "file": "a.png"
                }
              ],
              "version": 1
            }

            """)
    }

    @Test func numberArraysStayOnOneLine() {
        let value: JSONValue = .object([
            "crop": .array([.number(0), .number(88), .number(1920), .number(992)]),
            "empty": .array([]),
            "mixed": .array([.number(1), .string("a")]),
        ])
        #expect(text(value) == """
            {
              "crop": [0, 88, 1920, 992],
              "empty": [],
              "mixed": [
                1,
                "a"
              ]
            }

            """)
    }

    @Test func numbersAreRoundedToTwoDecimalsWithoutTrailingZeros() {
        let numbers: [(Double, String)] = [
            (1, "1"),
            (-3, "-3"),
            (412.5, "412.5"),
            (412.504, "412.5"),
            (0.125, "0.13"),
            (2.999, "3"),
            (-0.001, "0"),
            (1518, "1518"),
        ]
        for (number, expected) in numbers {
            #expect(text(.number(number)) == expected + "\n")
        }
    }

    @Test func stringsEscapeOnlyWhatJSONRequires() {
        let value: JSONValue = .string("Chọn VM \"web\"\\path/x\n\t\u{1}")
        #expect(text(value) == #""Chọn VM \"web\"\\path/x\n\t\u0001""# + "\n")
    }

    @Test func writtenBytesParseBackToTheSameValue() throws {
        let value: JSONValue = .object([
            "a": .array([.object(["k": .null, "t": .bool(true)]), .array([])]),
            "b": .string("ạ/ü"),
            "c": .number(12.25),
        ])
        #expect(try JSONValue.parse(SidecarWriter.data(value)) == value)
    }
}
