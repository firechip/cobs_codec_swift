// swift-tools-version: 6.0
//
// Package manifest for the `cobs_codec` package (repository `cobs_codec_swift`),
// a pure-Swift COBS / COBS-R codec.
//
// The `CobsCodec` library target is Swift-standard-library-only (no Foundation,
// no Apple frameworks, no external dependencies) so it stays portable to Linux
// and embedded Swift. The test target may use Foundation for JSON parsing.

import PackageDescription

let package = Package(
    name: "cobs_codec",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "CobsCodec",
            targets: ["CobsCodec"]
        )
    ],
    targets: [
        .target(
            name: "CobsCodec"
        ),
        // Dev-only throughput benchmark; not part of the shipped library.
        .executableTarget(
            name: "cobs-bench",
            dependencies: ["CobsCodec"]
        ),
        .testTarget(
            name: "CobsCodecTests",
            dependencies: ["CobsCodec"]
        ),
    ]
)
