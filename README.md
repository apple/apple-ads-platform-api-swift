# Apple Ads Platform API for Swift

[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fapple%2Fapple-ads-platform-api-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/apple/apple-ads-platform-api-swift)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fapple%2Fapple-ads-platform-api-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/apple/apple-ads-platform-api-swift)

A Swift client library for the Apple Ads platform API.

## Documentation

This README serves as the primary documentation for installation and usage of this library. For
information on data models and API endpoints, consult the
[Apple Ads Platform API documentation](https://developer.apple.com/documentation/apple-ads-platform-api)
found on Apple's developer website.

## Installation

Add the dependency to your `Package.swift`:

```swift
.package(url: "https://github.com/apple/apple-ads-platform-api-swift", from: "1.0.0")
```

Add the library product to your target:

```swift
.product(name: "AppleAdsClient", package: "apple-ads-platform-api-swift")
```

## Getting Started

This library provides a client for the Apple Ads Platform API. Built on
[Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator), it handles
authentication, token lifecycle management, and request authentication transparently.

### Client Construction

There are three ways to instantiate a client. All are valid and will result in a working client.

#### Using Your Private Key

Provide your private key along with the rest of the associated metadata. The library will create
a client secret using your private key every time a new access token is needed, and will
proactively refresh tokens before they expire.

```swift
import AppleAdsClient

let pemKey = try String(contentsOfFile: "/path/to/AuthKey.p8", encoding: .utf8)

try await AppleAdsClient.withClient(
    configuration: .init(
        clientId: "SEARCHADS.your-client-id",
        authMode: .key(teamId: "your-team-id", keyId: "your-key-id", privateKeyPEM: pemKey)
    )
) { client in
    // use client...
}
```

#### Using a Custom `ClientSecretProvider`

You may wish to generate client secrets in some other fashion. In this case,
provide an instance conforming to `ClientSecretProvider`. It will be called upon whenever a client
secret is needed for fetching a new access token.

```swift
import AppleAdsClient

// MySecretProvider must conform to ClientSecretProvider
let secretProvider = MySecretProvider(...)

try await AppleAdsClient.withClient(
    configuration: .init(
        clientId: "SEARCHADS.your-client-id",
        authMode: .clientSecretProvider(secretProvider)
    )
) { client in
    // use client...
}
```

#### Implementing Token Management Yourself

Although allowing this library to perform the OAuth flow is recommended, if you have unique needs
you may wish to implement that yourself. In this case, provide an instance conforming to
`TokenProvider`. It will be called upon before every API request in order to attach an access
token as an HTTP header. No caching or refresh logic is applied by the SDK in this mode.

```swift
import AppleAdsClient

// MyTokenProvider must conform to TokenProvider
let tokenProvider = MyTokenProvider(...)

try await AppleAdsClient.withClient(
    configuration: .init(
        clientId: "SEARCHADS.your-client-id",
        authMode: .tokenProvider(tokenProvider)
    )
) { client in
    // use client...
}
```

## Examples

#### Query Campaigns

```swift
let pemKey = try String(contentsOfFile: "/path/to/AuthKey.p8", encoding: .utf8)

let config = AppleAdsClient.Configuration(
    clientId: "SEARCHADS.your-client-id",
    authMode: .key(teamId: "your-team-id", keyId: "your-key-id", privateKeyPEM: pemKey)
)

try await AppleAdsClient.withClient(
    configuration: config
) { client in
    let contextHeader = XApContext(adAccountID: 12345).rawValue

    let response = try await client.postCampaignsQuery(
        headers: .init(xApContext: contextHeader),
        body: .json(.init())
    )
}
```

#### Get a Campaign by ID

```swift
let pemKey = try String(contentsOfFile: "/path/to/AuthKey.p8", encoding: .utf8)

let config = AppleAdsClient.Configuration(
    clientId: "SEARCHADS.your-client-id",
    authMode: .key(teamId: "your-team-id", keyId: "your-key-id", privateKeyPEM: pemKey)
)

try await AppleAdsClient.withClient(
    configuration: config
) { client in
    let contextHeader = XApContext(adAccountID: 12345).rawValue

    let response = try await client.getCampaignsId(
        path: .init(id: "your-campaign-id"),
        headers: .init(xApContext: contextHeader)
    )
}
```

## Server Usage

For server applications using `swift-service-lifecycle`, the `ServiceLifecycle` trait is enabled
by default. This allows `AppleAdsClient` to be used as a long-running `Service` that keeps tokens
fresh until graceful shutdown.

```swift
import AppleAdsClient
import Logging
import ServiceLifecycle

let logger = Logger(label: "com.example.ads")

try await withLogger(logger) { _ in
    let adsService = try await AppleAdsClient(
        configuration: .init(
            clientId: "SEARCHADS.your-client-id",
            authMode: .key(teamId: "your-team-id", keyId: "your-key-id", privateKeyPEM: pemKey)
        )
    )

    // adsService.client is ready - use it in request handlers
    let serviceGroup = ServiceGroup(
        services: [adsService],
        gracefulShutdownSignals: [.sigterm, .sigint],
        logger: logger
    )
    try await serviceGroup.run()
}
```

## Configuration from Environment

The `Configuration` package trait (enabled by default) adds an initializer that reads
from a `ConfigReader`:

```swift
import Configuration

let config = ConfigReader(provider: EnvironmentVariablesProvider())
let adsConfig = try AppleAdsClient.Configuration(config: config)
```

Required keys: `clientId`, `teamId`, `keyId`, `privateKeyPEM`.
Optional: `baseURL`, `authBaseURL`, `authTimeout`.

## Keeping Your Credentials Secure

Your private key and any client secrets you create are secrets. Do not store them as plain text.
Treat access tokens as secrets too. The library takes care not to log any of these values, and you
should take equal care if you add custom middleware to avoid logging `Authorization` headers or
token values.

## Thread Safety

`AppleAdsClient` is `Sendable`. Create a single instance and share it across your entire
application. This maximizes the benefit of connection pooling and minimizes calls to the OAuth
server. If you provide your own `TokenProvider`, thread safety will depend on your implementation.

## Enum Types

Enums from the OpenAPI spec are represented as structs with static constants. This ensures
forward compatibility - new values added server-side decode without throwing. Use a `default`
case in switches to handle values not yet known at compile time:

```swift
switch campaign.status {
case .active: ...
case .paused: ...
default: print("Unknown: \(campaign.status.rawValue)")
}
```

## License

This project is released under the MIT License. See [LICENSE](LICENSE) for details.
