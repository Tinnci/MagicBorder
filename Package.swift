// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "MagicBorder",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MagicBorderKit", targets: ["MagicBorderKit"]),
        .executable(name: "MagicBorder", targets: ["MagicBorder"]),
        .executable(name: "MagicBorderCLI", targets: ["MagicBorderCLI"]),
    ],
    targets: [
        .target(
            name: "MagicBorderKit",
            swiftSettings: sharedSwiftSettings),
        .executableTarget(
            name: "MagicBorder",
            dependencies: ["MagicBorderKit"],
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/Assets.xcassets"),
            ],
            swiftSettings: sharedSwiftSettings),
        .executableTarget(
            name: "MagicBorderCLI",
            dependencies: ["MagicBorderKit"],
            swiftSettings: sharedSwiftSettings),
        .testTarget(
            name: "MagicBorderKitTests",
            dependencies: ["MagicBorderKit"],
            swiftSettings: sharedSwiftSettings),
    ])
