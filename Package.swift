// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShadowVim",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .library(name: "Nvim", targets: ["Nvim"]),
    ],
    dependencies: [
        .package(url: "https://github.com/a2/MessagePack.swift.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "Nvim",
            dependencies: [
                "Toolkit",
                .product(name: "MessagePack", package: "MessagePack.swift"),
            ]
        ),
        .testTarget(
            name: "NvimTests",
            dependencies: [
                "Nvim",
            ]
        ),
        .target(
            name: "Toolkit"
        ),
    ]
)
