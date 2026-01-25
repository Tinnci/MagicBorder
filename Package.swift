// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MagicBorder",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MagicBorderKit", targets: ["MagicBorderKit"]),
        .executable(name: "MagicBorder", targets: ["MagicBorder"]),
        .executable(name: "MagicBorderCLI", targets: ["MagicBorderCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "MagicBorderKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            linkerSettings: []
        ),
        .executableTarget(
            name: "MagicBorder",
            dependencies: ["MagicBorderKit"],
            resources: [.process("Resources")],
            linkerSettings: []
        ),
        .executableTarget(
            name: "MagicBorderCLI",
            dependencies: ["MagicBorderKit"],
            linkerSettings: []
        ),
    ]
)
