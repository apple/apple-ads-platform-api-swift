// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import AsyncHTTPClient
import Logging
import OpenAPIAsyncHTTPClient
import OpenAPIRuntime
import Foundation

/// A client for the Apple Search Ads API.
///
/// `AppleAdsClient` handles authentication, token lifecycle management,
/// and request signing. It supports three authentication modes: a private
/// key, a ``ClientSecretProvider``, or a custom ``TokenProvider``.
///
/// ## Usage
///
/// **Scoped access** - runs a closure then tears down resources:
///
/// ```swift
/// let campaigns = try await AppleAdsClient.withClient(
///     configuration: config
/// ) { client in
///     try await client.queryAppDetails(...)
/// }
/// ```
///
/// **Long-running service** - requires the `ServiceLifecycle` trait:
///
/// ```swift
/// let adsClient = try await AppleAdsClient(configuration: config)
/// // adsClient.client is ready immediately
/// ```
///
/// ## Logging
///
/// `AppleAdsClient` reads `Logger.current` (the task-local logger from
/// swift-log SLG-0006) at call time. Bind a logger upstream via
/// `withLogger(_:_:)` - typically once at your application entry point.
///
/// ## Thread safety
///
/// `AppleAdsClient` is `Sendable`. The ``client`` property can be
/// shared freely across concurrency domains.
public struct AppleAdsClient: Sendable {

    /// Library version.
    static let version = "1.17.0"

    #if SERVICE_LIFECYCLE
    /// The configured API client, ready for making requests.
    ///
    /// Available immediately after initialization. Don't use after
    /// ``run()`` returns - the transport is shut down.
    public let client: Client

    private let tokenProvider: CachingTokenProvider?
    private let managedHTTPClient: HTTPClient?
    private let _logger: Logger
    #endif

    /// Run a closure with a fully managed Apple Ads API client.
    ///
    /// Creates the client, authenticates, runs your closure, then tears
    /// down all resources - regardless of whether `body` succeeds or
    /// throws.
    ///
    /// ```swift
    /// let result = try await AppleAdsClient.withClient(
    ///     configuration: .init(
    ///         clientId: "SEARCHADS.your-client-id",
    ///         authMode: .key(
    ///             teamId: "ABC",
    ///             keyId: "XYZ",
    ///             privateKeyPEM: pem
    ///         )
    ///     )
    /// ) { client in
    ///     try await client.queryAppDetails(...)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - configuration: Client configuration.
    ///   - transport: OpenAPI `ClientTransport`. Defaults to
    ///     `AsyncHTTPClientTransport()`.
    ///   - body: Closure that receives the configured client.
    /// - Returns: The value returned by `body`.
    /// - Throws: ``AppleAdsAuthError`` if the initial token fetch fails,
    ///   or re-throws any error from `body`.
    public static func withClient<Result>(
        configuration: Configuration,
        transport: any ClientTransport = AsyncHTTPClientTransport(),
        body: (Client) async throws -> Result
    ) async throws -> Result {
        let authHTTPClient: HTTPClient? =
            configuration.authMode.needsHTTPClient ? HTTPClient() : nil

        do {
            let (client, tokenProvider) = try await connect(
                configuration: configuration,
                transport: transport,
                httpClient: authHTTPClient
            )
            let result = try await body(client)
            await tokenProvider?.close()
            if let authHTTPClient {
                do {
                    try await authHTTPClient.shutdown()
                } catch {
                    Logger.current.warning(
                        "Auth HTTPClient shutdown failed",
                        metadata: ["error": "\(error)"]
                    )
                }
            }
            return result
        } catch {
            if let authHTTPClient {
                do {
                    try await authHTTPClient.shutdown()
                } catch let shutdownError {
                    Logger.current.error(
                        "Auth HTTPClient shutdown failed during error recovery",
                        metadata: ["error": "\(shutdownError)"]
                    )
                }
            }
            throw error
        }
    }

    // MARK: - Internal

    /// Create an OpenAPI `Client` with the configured auth middleware.
    ///
    /// - Parameters:
    ///   - configuration: Client configuration.
    ///   - transport: The OpenAPI transport for API requests.
    ///   - httpClient: `HTTPClient` for OAuth token exchange; `nil` for
    ///     `.tokenProvider` mode.
    /// - Returns: A configured `Client` and optional
    ///   `CachingTokenProvider`.
    /// - Throws: ``AppleAdsAuthError`` if the initial token fetch fails.
    static func connect(
        configuration: Configuration,
        transport: any ClientTransport,
        httpClient: HTTPClient?
    ) async throws -> (Client, CachingTokenProvider?) {
        let resolvedBaseURL =
            configuration.baseURL
            ?? ClientConstants.defaultBaseURL
        let resolvedAuthBaseURL =
            configuration.authBaseURL
            ?? AuthConstants.defaultAuthBaseURL

        let tokenProvider: any TokenProvider
        var managedCachingProvider: CachingTokenProvider?

        switch configuration.authMode.storage {
        case .key(let teamId, let keyId, let privateKeyPEM):
            guard let httpClient else {
                preconditionFailure("HTTPClient required for .key auth mode")
            }
            let signer = try JWTSigner(pemKey: privateKeyPEM, keyID: keyId)

            let fetcher = AccessTokenFetcher(
                authBaseURL: resolvedAuthBaseURL,
                clientId: configuration.clientId,
                teamId: teamId,
                signer: signer,
                httpClient: httpClient,
                timeout: configuration.authTimeout
            )

            let cachingProvider = try await CachingTokenProvider(
                onProactiveRefreshFailure: { error in
                    Logger.current.warning(
                        "Proactive token refresh failed; relying on reactive 401 handling as fallback",
                        metadata: ["component": "token-refresh", "error": "\(error)"]
                    )
                },
                fetchToken: {
                    try await fetcher.fetch()
                }
            )
            tokenProvider = cachingProvider
            managedCachingProvider = cachingProvider

        case .clientSecretProvider(let secretProvider):
            guard let httpClient else {
                preconditionFailure("HTTPClient required for .clientSecretProvider auth mode")
            }
            let fetcher = AccessTokenFetcher(
                authBaseURL: resolvedAuthBaseURL,
                clientId: configuration.clientId,
                clientSecretProvider: secretProvider,
                httpClient: httpClient,
                timeout: configuration.authTimeout
            )

            let cachingProvider = try await CachingTokenProvider(
                onProactiveRefreshFailure: { error in
                    Logger.current.warning(
                        "Proactive token refresh failed; relying on reactive 401 handling as fallback",
                        metadata: ["component": "token-refresh", "error": "\(error)"]
                    )
                },
                fetchToken: {
                    try await fetcher.fetch()
                }
            )
            tokenProvider = cachingProvider
            managedCachingProvider = cachingProvider

        case .tokenProvider(let customProvider):
            tokenProvider = customProvider
        }

        let middlewares: [any ClientMiddleware] =
            [
                UserAgentMiddleware(),
                AuthMiddleware(tokenProvider: tokenProvider),
                HeaderFixupMiddleware(),
            ]
            + configuration.middleware

        let client = Client(
            serverURL: resolvedBaseURL,
            configuration: .init(dateTranscoder: AppleAdsDateTranscoder()),
            transport: transport,
            middlewares: middlewares
        )

        return (client, managedCachingProvider)
    }
}

// MARK: - Service Conformance

#if SERVICE_LIFECYCLE
import ServiceLifecycle

extension AppleAdsClient: Service {

    /// Create a client configured for use as a long-running `Service`.
    ///
    /// Authenticates during initialization (fails fast on invalid
    /// credentials) and keeps tokens fresh until graceful shutdown.
    /// Requires the `ServiceLifecycle` package trait.
    ///
    /// Captures `Logger.current` at initialization and uses it during
    /// ``run()``. Bind a logger with `withLogger` around this initializer,
    /// not around ``run()``.
    ///
    /// ```swift
    /// let adsClient = try await AppleAdsClient(
    ///     configuration: .init(
    ///         clientId: "SEARCHADS.your-client-id",
    ///         authMode: .key(
    ///             teamId: "...",
    ///             keyId: "...",
    ///             privateKeyPEM: pem
    ///         )
    ///     )
    /// )
    ///
    /// let serviceGroup = ServiceGroup(
    ///     services: [adsClient],
    ///     gracefulShutdownSignals: [.sigterm, .sigint],
    ///     logger: Logger.current
    /// )
    /// try await serviceGroup.run()
    /// ```
    ///
    /// - Parameters:
    ///   - configuration: Client configuration.
    ///   - transport: OpenAPI `ClientTransport`. Defaults to
    ///     `AsyncHTTPClientTransport()`.
    /// - Throws: ``AppleAdsAuthError`` if the initial token fetch fails.
    nonisolated(nonsending)
        public init(
            configuration: Configuration,
            transport: any ClientTransport = AsyncHTTPClientTransport()
        ) async throws
    {
        let logger = Logger.current
        let authHTTPClient: HTTPClient? =
            configuration.authMode.needsHTTPClient ? HTTPClient() : nil

        do {
            let (client, tokenProvider) = try await AppleAdsClient.connect(
                configuration: configuration,
                transport: transport,
                httpClient: authHTTPClient
            )
            self.client = client
            self.tokenProvider = tokenProvider
            self.managedHTTPClient = authHTTPClient
            self._logger = logger
        } catch {
            if let authHTTPClient {
                try? await authHTTPClient.shutdown()
            }
            throw error
        }
    }

    /// Suspend until graceful shutdown, then stop token refresh and
    /// shut down the internal HTTP client.
    ///
    /// Called by `ServiceGroup` - you don't call this directly.
    public func run() async throws {
        self._logger.info("AppleAdsClient started")
        try await gracefulShutdown()
        await self.tokenProvider?.close()
        if let managedHTTPClient {
            try await managedHTTPClient.shutdown()
        }
        self._logger.info("AppleAdsClient stopped")
    }
}
#endif
