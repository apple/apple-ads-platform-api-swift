apple-ads-platform-api-swift Development Guide
=============================================

## Formatting

This project uses [swift-format](https://github.com/swiftlang/swift-format). Before submitting a PR, format your changes:

```bash
./scripts/format.sh
```

You can verify formatting without modifying files:

```bash
./scripts/lint.sh
```

Generated code (`Sources/AppleAdsClient/Generated/`) is excluded from formatting checks.

## Running Tests

```bash
swift test
```

The `ServiceLifecycle` and `Configuration` traits are enabled by default. To test without them:

```bash
swift test --disable-default-traits
```

This requires the `swift-openapi-generator` CLI in your PATH.
See the [swift-openapi-generator repository](https://github.com/apple/swift-openapi-generator) for installation.
