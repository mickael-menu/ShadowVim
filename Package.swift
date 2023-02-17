// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShadowVim",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(name: "AX", targets: ["AX"]),
        .library(name: "Mediator", targets: ["Mediator"]),
        .library(name: "Nvim", targets: ["Nvim"]),
        .library(name: "Toolkit", targets: ["Toolkit"]),

        .library(name: "NSLoggerAdapter", targets: ["NSLoggerAdapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/a2/MessagePack.swift.git", from: "4.0.0"),
        .package(url: "https://github.com/fpillet/NSLogger.git", branch: "master"),
        .package(url: "https://github.com/Clipy/Sauce.git", from: "2.3.0"),
    ],
    targets: [
        .target(
            name: "AX",
            dependencies: [
                "Toolkit",
            ]
        ),
        .target(
            name: "Mediator",
            dependencies: [
                "AX",
                "Nvim",
                "Toolkit",
            ]
        ),
        .testTarget(
            name: "MediatorTests",
            dependencies: [
                "Mediator",
            ]
        ),
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
            name: "Toolkit",
            dependencies: [
                "Sauce",
            ]
        ),
        .target(
            name: "NSLoggerAdapter",
            dependencies: ["Toolkit", .product(name: "NSLogger", package: "NSLogger")],
            path: "Sources/Adapters/NSLogger"
        ),
    ]
)
