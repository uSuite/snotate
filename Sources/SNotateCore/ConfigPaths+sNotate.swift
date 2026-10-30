import Foundation
import SCommon

/// sNotate's files live in `~/.config/snotate/` (DECISIONS 2026-10-25).
extension ConfigPaths {
    public static func snotate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ConfigPaths {
        ConfigPaths(
            app: "snotate",
            environment: environment,
            home: home
        )
    }
}
