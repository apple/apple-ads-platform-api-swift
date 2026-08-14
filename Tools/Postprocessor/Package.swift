// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Postprocessor",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "postprocessor",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "PostprocessorTests",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Tests"
        ),
    ]
)
