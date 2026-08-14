// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

/// A type that provides access tokens for API authentication.
///
/// Conforming types manage their own token lifecycle (fetching, caching,
/// refreshing). The SDK calls ``token()`` before each request and trusts
/// the returned value is valid.
///
/// ## Example
///
/// ```swift
/// struct MyTokenProvider: TokenProvider {
///     func token() async throws -> String {
///         // Return the raw access token (without "Bearer " prefix)
///         try await fetchFromVault()
///     }
/// }
/// ```
public protocol TokenProvider: Sendable {
    /// Returns a valid access token string.
    ///
    /// - Returns: The raw access token without a scheme prefix. The SDK
    ///   prepends `"Bearer "` when constructing the `Authorization` header.
    /// - Throws: Any error encountered while obtaining the token. The SDK
    ///   may retry on subsequent requests.
    nonisolated(nonsending) func token() async throws -> String
}
