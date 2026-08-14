// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

/// A type that provides client secrets (signed JWTs) for the OAuth token exchange.
///
/// Use this when your private key lives in an HSM, Vault, or external signing
/// service. The SDK handles the token exchange, caching, and proactive
/// refresh - you only provide the signed client secret JWT.
///
/// ## Example
///
/// ```swift
/// struct VaultSecretProvider: ClientSecretProvider {
///     func clientSecret() async throws -> String {
///         try await vault.signClientSecret()
///     }
/// }
/// ```
public protocol ClientSecretProvider: Sendable {
    /// Returns a signed client secret JWT for the OAuth token exchange.
    ///
    /// - Returns: A signed JWT string used as the `client_secret` form
    ///   parameter in the token request.
    /// - Throws: Any error encountered while producing the JWT. The SDK
    ///   may retry on a subsequent token refresh cycle.
    nonisolated(nonsending) func clientSecret() async throws -> String
}
