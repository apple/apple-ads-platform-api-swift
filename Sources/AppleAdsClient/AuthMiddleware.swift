// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import HTTPTypes
import OpenAPIRuntime
import Foundation

/// Middleware that injects Bearer tokens and retries once on 401.
///
/// On retry, the same `body` is passed to `next`. This is safe because
/// the generated client produces buffer-backed bodies that support
/// multiple reads. Stream-backed bodies will throw on retry.
internal struct AuthMiddleware: ClientMiddleware, Sendable {
    private let tokenProvider: any TokenProvider
    private let scheme: String

    /// Creates an auth middleware.
    ///
    /// - Parameters:
    ///   - tokenProvider: The provider that supplies access tokens.
    ///   - scheme: The authorization scheme. Defaults to `"Bearer"`.
    internal init(tokenProvider: any TokenProvider, scheme: String = "Bearer") {
        self.tokenProvider = tokenProvider
        self.scheme = scheme
    }

    /// Intercepts the request to inject a bearer token, retrying once on 401.
    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var authedRequest = request
        let currentToken = try await self.tokenProvider.token()
        authedRequest.headerFields[.authorization] = "\(self.scheme) \(currentToken)"

        let (response, responseBody) = try await next(authedRequest, body, baseURL)

        guard response.status == .unauthorized else {
            return (response, responseBody)
        }

        guard AuthConstants.maxRequestAttempts > 1 else {
            return (response, responseBody)
        }

        // On failed refresh, return original 401 response to caller.
        let freshToken: String
        do {
            freshToken = try await self.tokenProvider.token()
        } catch {
            return (response, responseBody)
        }

        guard freshToken != currentToken else {
            return (response, responseBody)
        }

        var retryRequest = request
        retryRequest.headerFields[.authorization] = "\(self.scheme) \(freshToken)"

        return try await next(retryRequest, body, baseURL)
    }
}
