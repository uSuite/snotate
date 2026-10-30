import Foundation
import Testing
@testable import SNotateCore

struct ConfigPathsTests {
    @Test func filesLiveInDotConfigSnotate() {
        let paths = ConfigPaths.snotate(
            environment: [:],
            home: URL(fileURLWithPath: "/Users/me")
        )
        #expect(paths.directory.path == "/Users/me/.config/snotate")
        #expect(paths.config.path == "/Users/me/.config/snotate/config")
        #expect(paths.keymap.path == "/Users/me/.config/snotate/keymap")
        #expect(paths.state.path == "/Users/me/.config/snotate/state.json")
    }

    @Test func xdgConfigHomeIsHonoured() {
        let paths = ConfigPaths.snotate(
            environment: ["XDG_CONFIG_HOME": "/xdg"],
            home: URL(fileURLWithPath: "/Users/me")
        )
        #expect(paths.directory.path == "/xdg/snotate")
    }
}
