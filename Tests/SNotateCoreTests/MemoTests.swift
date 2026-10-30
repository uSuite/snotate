import Foundation
import Testing
@testable import SNotateCore

struct MemoTests {
    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Fixtures.url("memos/\(name).md"))
    }

    static func memo(_ name: String) throws -> Memo {
        try Memo(data: fixture(name))
    }

    static let allFixtures = [
        "lf",
        "crlf",
        "trailing-spaces",
        "duplicate-reference",
        "sub-bullets",
        "no-bullets",
        "utf8-vietnamese",
        "placeholders",
        "assets-subbullets",
    ]

    @Test(arguments: allFixtures)
    func bytesRoundTripUnchanged(name: String) throws {
        let data = try Self.fixture(name)
        #expect(try Memo(data: data).bytes == data)
    }

    @Test func lfAndCRLFGiveTheSameCaptions() throws {
        for name in ["lf", "crlf"] {
            let memo = try Self.memo(name)
            #expect(memo.entry(for: "poc-memo-sample-00.png")?.caption == "First step")
            #expect(memo.entry(for: "poc-memo-sample-01.png")?.caption == "Second step")
            #expect(memo.entry(for: "poc-memo-sample-01.png")?.bulletLine == 6)
            #expect(memo.entry(for: "poc-memo-sample-01.png")?.imageLine == 8)
        }
        #expect(try Self.memo("crlf").lines[2].ending == "\r\n")
    }

    @Test func trailingWhitespaceIsNotPartOfTheCaption() throws {
        #expect(try Self.memo("trailing-spaces").entry(for: "poc-memo-sample-00.png")?.caption == "First step")
        // A line of spaces between bullet and image counts as blank.
        #expect(try Self.memo("trailing-spaces").entry(for: "poc-memo-sample-01.png")?.caption == "Second step")
    }

    @Test func aSecondReferenceIsReportedNotUsed() throws {
        let memo = try Self.memo("duplicate-reference")
        let references = memo.references(to: "poc-memo-sample-00.png")
        #expect(references.map(\.caption) == ["First step", "The first capture again, for comparison"])
        #expect(memo.entry(for: "poc-memo-sample-00.png") == references[0])
    }

    @Test func subBulletsBelongToTheBulletAbove() throws {
        let entry = try Self.memo("sub-bullets").entry(for: "poc-memo-sample-01.png")
        #expect(entry?.caption == "Second step")
        #expect(entry?.details == ["  - Turn it on.", "  - Define **Rule Sets**: Ingress/Egress."])
    }

    @Test func imagesWithoutABulletHaveNoCaption() throws {
        let memo = try Self.memo("no-bullets")
        for file in ["poc-memo-sample-00.png", "poc-memo-sample-01.png"] {
            let entry = memo.entry(for: file)
            #expect(entry != nil)
            #expect(entry?.bulletLine == nil)
            #expect(entry?.caption == nil)
        }
    }

    @Test func vietnameseTextIsRead() throws {
        #expect(try Self.memo("utf8-vietnamese").entry(for: "poc-memo-sample-00.png")?.caption == "Bước đầu tiên: chọn VM đang chạy")
    }

    @Test func placeholderBulletsCountAsUnwritten() throws {
        let memo = try Self.memo("placeholders")
        #expect(memo.entries.count == 6)
        #expect(memo.entries.allSatisfy { $0.caption == "description" && $0.isPlaceholder })
    }

    @Test func memoWithAssetsPathsAndSubBullets() throws {
        let memo = try Self.memo("assets-subbullets")
        #expect(memo.entries.count == 20)
        #expect(memo.entries.allSatisfy { $0.file.hasPrefix("assets/scap-2026-10-22-") && $0.caption != nil })
        let entry = memo.entry(for: "assets/scap-2026-10-22-160446.png")
        #expect(entry?.caption == "Members can switch workspaces from the drop-down list.")
        #expect(entry?.details == ["  - Let’s select DEMO-TEAM."])
        #expect(memo.entry(for: "scap-2026-10-22-160446.png") == nil)
    }

    @Test func pathsAreNormalisedAndFencesSkipped() throws {
        let text = """
            # poc-x-y-z

            - Dot slash

            ![a](./a.png)

            - Spaces

            ![b](<my shot.png> "title")

            - Encoded

            ![c](my%20other.png)

            ```
            - Not a caption

            ![d](d.png)
            ```
            """
        let memo = try Memo(data: Data(text.utf8))
        #expect(memo.entry(for: "a.png")?.caption == "Dot slash")
        #expect(memo.entry(for: "my shot.png")?.caption == "Spaces")
        #expect(memo.entry(for: "my other.png")?.caption == "Encoded")
        #expect(memo.entry(for: "d.png") == nil)
        #expect(memo.bytes == Data(text.utf8))
    }

    @Test func aByteOrderMarkAndAMissingFinalNewlineSurvive() throws {
        let data = Data("\u{FEFF}- First\n\n![a](a.png)".utf8)
        let memo = try Memo(data: data)
        #expect(memo.entry(for: "a.png")?.caption == "First")
        #expect(memo.lines.last?.ending == "")
        #expect(memo.bytes == data)
    }

    @Test func otherEncodingsAreRefused() {
        #expect(throws: MemoError.notUTF8) {
            try Memo(data: Data([0x2d, 0x20, 0xff, 0xfe, 0x0a]))
        }
    }
}

struct MemoRewriteTests {
    @Test(arguments: MemoTests.allFixtures)
    func settingACaptionChangesExactlyTheBulletLine(name: String) throws {
        let memo = try MemoTests.memo(name)
        let files = memo.entries.map(\.file)
        for file in Set(files) {
            guard let entry = memo.entry(for: file), let bulletLine = entry.bulletLine else {
                continue
            }
            let changed = try Memo(data: memo.settingCaption("Bấm **Start** ✓", for: file))
            #expect(changed.lines.count == memo.lines.count)
            let differing = changed.lines.indices.filter { changed.lines[$0] != memo.lines[$0] }
            #expect(differing == [bulletLine])
            #expect(changed.lines[bulletLine].ending == memo.lines[bulletLine].ending)
            #expect(changed.entry(for: file)?.caption == "Bấm **Start** ✓")
        }
    }

    @Test func markerAndTrailingWhitespaceAreKept() throws {
        let memo = try MemoTests.memo("trailing-spaces")
        let changed = try Memo(data: memo.settingCaption("Changed", for: "poc-memo-sample-00.png"))
        #expect(changed.lines[2].text == "- Changed   ")
        let star = try Memo(data: Data("*   Old\n\n![a](a.png)\n".utf8))
        #expect(try star.settingCaption("New", for: "a.png") == Data("*   New\n\n![a](a.png)\n".utf8))
    }

    @Test func crlfStaysCRLF() throws {
        let data = try MemoTests.memo("crlf").settingCaption("Changed", for: "poc-memo-sample-01.png")
        #expect(String(decoding: data, as: UTF8.self).contains("- Changed\r\n\r\n![poc-memo-sample-01]"))
        #expect(!String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    @Test func onlyTheFirstOfTwoReferencesChanges() throws {
        let memo = try MemoTests.memo("duplicate-reference")
        let changed = try Memo(data: memo.settingCaption("Changed", for: "poc-memo-sample-00.png"))
        #expect(changed.references(to: "poc-memo-sample-00.png").map(\.caption) == ["Changed", "The first capture again, for comparison"])
    }

    @Test func anImageWithoutABulletGetsOneInsertedAbove() throws {
        let memo = try MemoTests.memo("no-bullets")
        let first = try memo.settingCaption("First", for: "poc-memo-sample-00.png")
        #expect(String(decoding: first, as: UTF8.self).hasPrefix("# poc-memo-sample\n\n- First\n\n![poc-memo-sample-00](poc-memo-sample-00.png)\n"))
        let second = try Memo(data: memo.settingCaption("Second", for: "poc-memo-sample-01.png"))
        #expect(second.entry(for: "poc-memo-sample-01.png")?.caption == "Second")
        #expect(second.lines.count == memo.lines.count + 2)

        let prose = try Memo(data: Data("Prose\n![a](a.png)\n".utf8))
        #expect(try prose.settingCaption("New", for: "a.png") == Data("Prose\n\n- New\n\n![a](a.png)\n".utf8))
        let crlf = try Memo(data: Data("# t\r\n\r\n![a](a.png)".utf8))
        #expect(try crlf.settingCaption("New", for: "a.png") == Data("# t\r\n\r\n- New\r\n\r\n![a](a.png)".utf8))
        let alone = try Memo(data: Data("![a](a.png)".utf8))
        #expect(try alone.settingCaption("New", for: "a.png") == Data("- New\n\n![a](a.png)".utf8))
    }

    @Test func multiLineCaptionsAndUnknownFilesAreRefused() throws {
        let memo = try MemoTests.memo("lf")
        #expect(throws: MemoError.multiline) {
            try memo.settingCaption("one\ntwo", for: "poc-memo-sample-00.png")
        }
        #expect(throws: MemoError.multiline) {
            try memo.settingCaption("one\rtwo", for: "poc-memo-sample-00.png")
        }
        #expect(throws: MemoError.noReference("other.png")) {
            try memo.settingCaption("x", for: "other.png")
        }
    }
}

struct MemoFileTests {
    private func copy(_ name: String, in temp: TempFolder) throws -> URL {
        let url = temp.url.appendingPathComponent("\(name).md")
        try FileManager.default.copyItem(
            at: Fixtures.url("memos/\(name).md"),
            to: url
        )
        return url
    }

    @Test func writingACaptionChangesOneLineOnDisk() throws {
        let temp = try TempFolder()
        let url = try copy("crlf", in: temp)
        let memo = try Memo.read(url)
        let updated = try memo.writeCaption("Changed", for: "poc-memo-sample-00.png", to: url)
        #expect(try Data(contentsOf: url) == memo.settingCaption("Changed", for: "poc-memo-sample-00.png"))
        #expect(updated == (try Memo.read(url)))
        #expect(updated.entry(for: "poc-memo-sample-00.png")?.caption == "Changed")
        // The returned memo is the base for the next edit.
        _ = try updated.writeCaption("Again", for: "poc-memo-sample-01.png", to: url)
        #expect(try Memo.read(url).entries.map(\.caption) == ["Changed", "Again"])
    }

    @Test func aMemoChangedOnDiskIsNotOverwritten() throws {
        let temp = try TempFolder()
        let url = try copy("lf", in: temp)
        let memo = try Memo.read(url)
        let outside = Data("# poc-memo-sample\n\nEdited elsewhere.\n".utf8)
        try outside.write(to: url)
        #expect(throws: MemoError.changedOnDisk) {
            try memo.writeCaption("Changed", for: "poc-memo-sample-00.png", to: url)
        }
        #expect(try Data(contentsOf: url) == outside)
    }

    @Test func aMissingMemoIsUnreadable() {
        #expect {
            try Memo.read(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).md"))
        } throws: { error in
            guard case MemoError.unreadable = error else {
                return false
            }
            return true
        }
    }
}
