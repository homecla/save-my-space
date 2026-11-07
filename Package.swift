// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 homecla
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "save-my-space",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "smspace", targets: ["smspace"]),
        .executable(name: "SaveMySpaceApp", targets: ["SaveMySpaceApp"]),
        .library(name: "SaveMySpaceCore", targets: ["SaveMySpaceCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "SaveMySpaceCore"),
        .executableTarget(
            name: "smspace",
            dependencies: [
                "SaveMySpaceCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "SaveMySpaceApp", dependencies: ["SaveMySpaceCore"]),
        .testTarget(name: "SaveMySpaceCoreTests", dependencies: ["SaveMySpaceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
