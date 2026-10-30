import Foundation
import Testing
@testable import SNotateCore

struct CaseSiblingsTests {
    /// A product folder holding cases 1, 2 (captures only in `assets/`), 3
    /// (no captures) and 10, a product-named sub-folder and a folder of PNGs
    /// that is not a case.
    private func tree() throws -> (TempFolder, URL) {
        let temp = try TempFolder()
        try temp.file("poc-demo/poc-demo-vm-1/poc-demo-vm-1-00.png")
        try temp.file("poc-demo/poc-demo-vm-2/assets/scap-old.png")
        try temp.folder("poc-demo/poc-demo-vm-3")
        try temp.file("poc-demo/poc-demo-vm-10/poc-demo-vm-10-00.png")
        try temp.file("poc-demo/poc-demo-vm-10/notated/poc-demo-vm-10-00.png")
        try temp.file("poc-demo/golden/arrow.png")
        try temp.file("poc-demo/poc-demo/x.png")
        return (temp, temp.url.appendingPathComponent("poc-demo"))
    }

    private func name(_ url: URL?) -> String? {
        url?.lastPathComponent
    }

    @Test func casesFollowInNaturalOrderSkippingEmptyAndNonCaseFolders() throws {
        let (temp, root) = try tree()
        _ = temp
        let one = root.appendingPathComponent("poc-demo-vm-1")
        #expect(name(CaseSiblings.sibling(of: one, offset: 1)) == "poc-demo-vm-2")
        #expect(name(CaseSiblings.sibling(of: one, offset: 2)) == "poc-demo-vm-10")
        #expect(CaseSiblings.sibling(of: one, offset: 3) == nil)
        #expect(CaseSiblings.sibling(of: one, offset: -1) == nil)
        let ten = root.appendingPathComponent("poc-demo-vm-10")
        #expect(name(CaseSiblings.sibling(of: ten, offset: -2)) == "poc-demo-vm-1")
    }

    @Test func anEmptyOpenCaseStillHasNeighbours() throws {
        let (temp, root) = try tree()
        _ = temp
        let three = root.appendingPathComponent("poc-demo-vm-3")
        #expect(name(CaseSiblings.sibling(of: three, offset: -1)) == "poc-demo-vm-2")
        #expect(name(CaseSiblings.sibling(of: three, offset: 1)) == "poc-demo-vm-10")
    }

    @Test func outsideAPocTreeAnyFolderWithImagesCounts() throws {
        let temp = try TempFolder()
        try temp.file("shots/monday/a.png")
        try temp.file("shots/tuesday/a.png")
        try temp.folder("shots/wednesday")
        try temp.file("shots/poc-x-y-z/a.png")
        let monday = temp.url.appendingPathComponent("shots/monday")
        #expect(CaseSiblings.sibling(of: monday, offset: -1) == nil)
        #expect(name(CaseSiblings.sibling(of: monday, offset: 1)) == "poc-x-y-z")
        #expect(name(CaseSiblings.sibling(of: monday, offset: 2)) == "tuesday")
        #expect(CaseSiblings.sibling(of: monday, offset: 3) == nil)
    }
}
