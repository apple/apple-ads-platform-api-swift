// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Foundation
import OpenAPIRuntime

extension AppleAdsClient.Configuration: CustomStringConvertible {
    /// A redacted description that excludes sensitive credential material.
    public var description: String {
        "Configuration(clientId: \(clientId), authMode: \(authMode))"
    }
}

extension AppleAdsClient.Configuration.AuthMode: CustomStringConvertible {
    /// A redacted description that excludes the private key PEM.
    public var description: String {
        switch storage {
        case .key(let teamId, let keyId, _):
            return "key(teamId: \(teamId), keyId: \(keyId), privateKeyPEM: <redacted>)"
        case .clientSecretProvider:
            return "clientSecretProvider(...)"
        case .tokenProvider:
            return "tokenProvider(...)"
        }
    }
}

extension AppleAdsClient {
    /// Configuration for an ``AppleAdsClient`` instance.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let config = AppleAdsClient.Configuration(
    ///     clientId: "SEARCHADS.your-client-id",
    ///     authMode: .key(
    ///         teamId: "your-team-id",
    ///         keyId: "your-key-id",
    ///         privateKeyPEM: pemString
    ///     )
    /// )
    /// ```
    public struct Configuration: Sendable {

        /// The authentication strategy for the Apple Search Ads API.
        public struct AuthMode: Sendable {
            enum Storage: Sendable {
                case key(teamId: String, keyId: String, privateKeyPEM: String)
                case clientSecretProvider(any ClientSecretProvider)
                case tokenProvider(any TokenProvider)
            }

            let storage: Storage

            /// Whether this auth mode requires an `HTTPClient` for token fetching.
            var needsHTTPClient: Bool {
                switch storage {
                case .key, .clientSecretProvider:
                    return true
                case .tokenProvider:
                    return false
                }
            }

            /// Authenticate with a private key using JWT/ES256 signing.
            ///
            /// The SDK signs JWTs, exchanges them for access tokens, and
            /// refreshes tokens proactively before expiry.
            ///
            /// - Parameters:
            ///   - teamId: Your Apple Developer team ID.
            ///   - keyId: The identifier for your ES256 signing key.
            ///   - privateKeyPEM: The PEM-encoded ES256 private key.
            /// - Returns: An auth mode configured for key-based signing.
            public static func key(
                teamId: String,
                keyId: String,
                privateKeyPEM: String
            ) -> AuthMode {
                AuthMode(storage: .key(teamId: teamId, keyId: keyId, privateKeyPEM: privateKeyPEM))
            }

            /// Authenticate with a custom client secret provider.
            ///
            /// Use this when your signing key lives in an external system
            /// (a vault or HSM). The SDK exchanges each JWT for an access
            /// token and caches it.
            ///
            /// - Parameter provider: Produces signed client secret JWTs.
            /// - Returns: An auth mode configured with the given provider.
            public static func clientSecretProvider(
                _ provider: any ClientSecretProvider
            ) -> AuthMode {
                AuthMode(storage: .clientSecretProvider(provider))
            }

            /// Authenticate with a fully custom token provider.
            ///
            /// The SDK uses the returned bearer token directly - no
            /// caching or refresh logic is applied.
            ///
            /// - Parameter provider: Provides bearer tokens.
            /// - Returns: An auth mode configured with the given provider.
            public static func tokenProvider(
                _ provider: any TokenProvider
            ) -> AuthMode {
                AuthMode(storage: .tokenProvider(provider))
            }
        }

        /// Your `SEARCHADS.`-prefixed client identifier.
        public var clientId: String

        /// The authentication strategy to use.
        public var authMode: AuthMode

        /// The base URL for API requests.
        ///
        /// Defaults to `https://api.ads.apple.com/v1`.
        public var baseURL: URL?

        /// The base URL for OAuth token exchange requests.
        ///
        /// Defaults to Apple ID production.
        public var authBaseURL: URL?

        /// Timeout for the SDK's OAuth token fetch requests.
        ///
        /// Applies only to auth calls, not API requests.
        public var authTimeout: Duration

        /// Middleware for the request pipeline.
        ///
        /// Runs after the SDK's built-in middleware. Executes in array
        /// order.
        public var middleware: [any ClientMiddleware]

        /// Create a client configuration.
        ///
        /// - Parameters:
        ///   - clientId: Your `SEARCHADS.`-prefixed client identifier.
        ///   - authMode: The authentication strategy to use.
        ///   - baseURL: API base URL. Defaults to production.
        ///   - authBaseURL: OAuth token endpoint base URL. Defaults to
        ///     Apple ID production.
        ///   - authTimeout: Timeout for token fetch requests. Defaults
        ///     to 5 seconds.
        ///   - middleware: Middleware appended after the SDK's built-in
        ///     pipeline.
        public init(
            clientId: String,
            authMode: AuthMode,
            baseURL: URL? = nil,
            authBaseURL: URL? = nil,
            authTimeout: Duration = .seconds(5),
            middleware: [any ClientMiddleware] = []
        ) {
            self.clientId = clientId
            self.authMode = authMode
            self.baseURL = baseURL
            self.authBaseURL = authBaseURL
            self.authTimeout = authTimeout
            self.middleware = middleware
        }
    }
}
