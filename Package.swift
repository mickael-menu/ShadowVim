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
        .library(name: "SauceAdapter", targets: ["SauceAdapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/a2/MessagePack.swift.git", from: "4.0.0"),
        .package(url: "https://github.com/fpillet/NSLogger.git", branch: "master"),
        .package(url: "https://github.com/Clipy/Sauce.git", from: "2.3.0"),
        .package(url: "https://github.com/krzysztofzablocki/Difference.git", from: "1.0.0"),
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
                .product(name: "Difference", package: "Difference"),
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
                .product(name: "Difference", package: "Difference"),
            ]
        ),
        .target(
            name: "Toolkit",
            dependencies: []
        ),
        .testTarget(
            name: "ToolkitTests",
            dependencies: [
                "Toolkit",
                .product(name: "Difference", package: "Difference"),
            ]
        ),
        .target(
            name: "NSLoggerAdapter",
            dependencies: [
                "Toolkit",
                .product(name: "NSLogger", package: "NSLogger"),
            ],
            path: "Sources/Adapters/NSLogger"
        ),
        .target(
            name: "SauceAdapter",
            dependencies: [
                "Toolkit",
                .product(name: "Sauce", package: "Sauce"),
            ],
            path: "Sources/Adapters/Sauce"
        ),
    ]
)
