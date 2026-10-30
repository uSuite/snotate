// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The code shared with sView and sCapture: the sibling checkout when there
// is one, else the published package (DECISIONS 2026-10-30).
let sibling = URL(fileURLWithPath: Context.packageDirectory)
    .deletingLastPathComponent()
    .appendingPathComponent("scommon/Package.swift")
let scommon: Package.Dependency = FileManager.default.fileExists(atPath: sibling.path)
    ? .package(path: "../scommon")
    : .package(
        url: "https://github.com/uSuite/scommon.git",
        from: "0.3.0"
    )

let package = Package(
    name: "sNotate",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "SNotateCore",
            targets: ["SNotateCore"]
        ),
        .executable(
            name: "sNotate",
            targets: ["sNotate"]
        ),
        .executable(
            name: "snotate-cheatsheet",
            targets: ["snotate-cheatsheet"]
        ),
    ],
    dependencies: [
        scommon
    ],
    targets: [
        .target(
            name: "SNotateCore",
            dependencies: [
                .product(
                    name: "SCommon",
                    package: "scommon"
                )
            ]
        ),
        .executableTarget(
            name: "sNotate",
            dependencies: ["SNotateCore"]
        ),
        .executableTarget(
            name: "snotate-cheatsheet",
            dependencies: ["SNotateCore"]
        ),
        .testTarget(
            name: "SNotateCoreTests",
            dependencies: ["SNotateCore"]
        ),
    ]
)
