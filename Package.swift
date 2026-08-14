// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "apple-ads-platform-api-swift",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "AppleAdsClient", targets: ["AppleAdsClient"]),
    ],
    traits: [
        .default(enabledTraits: ["ServiceLifecycle", "Configuration"]),
        .trait(name: "ServiceLifecycle"),
        .trait(name: "Configuration"),
    ],
    dependencies: [
        // OpenAPI
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-async-http-client.git", from: "1.0.0"),

        // HTTP
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),

        // Crypto
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),

        // Logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),

        // Documentation
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.0"),

        // Lifecycle (conditional on trait)
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.3.0"),

        // Configuration (conditional on trait)
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
    ],
    targets: [
        // ── Client module (includes auth) ──────────────────────────────────
        .target(
            name: "AppleAdsClient",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle",
                         condition: .when(traits: ["ServiceLifecycle"])),
                .product(name: "Configuration", package: "swift-configuration",
                         condition: .when(traits: ["Configuration"])),
            ],
            exclude: ["openapi-generator-config.yaml"],
            swiftSettings: [
                .define("SERVICE_LIFECYCLE", .when(traits: ["ServiceLifecycle"])),
                .define("CONFIGURATION", .when(traits: ["Configuration"])),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),

        // ── Tests ────────────────────────────────────────────────────────
        .testTarget(
            name: "AppleAdsClientTests",
            dependencies: [
                "AppleAdsClient",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle",
                         condition: .when(traits: ["ServiceLifecycle"])),
                .product(name: "ServiceLifecycleTestKit", package: "swift-service-lifecycle",
                         condition: .when(traits: ["ServiceLifecycle"])),
            ],
            swiftSettings: [
                .define("SERVICE_LIFECYCLE", .when(traits: ["ServiceLifecycle"])),
            ]
        ),
    ]
)
