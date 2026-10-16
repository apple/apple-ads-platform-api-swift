// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import HTTPTypes
import OpenAPIRuntime
import Foundation

/// Middleware that injects Bearer tokens and retries on 401 up to ``AuthConstants/maxRequestAttempts`` times.
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

    /// Intercepts the request to inject a bearer token, retrying up to
    /// `AuthConstants.maxRequestAttempts - 1` times on 401 responses.
    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var lastToken = try await self.tokenProvider.token()
        var authedRequest = request
        authedRequest.headerFields[.authorization] = "\(self.scheme) \(lastToken)"

        var (response, responseBody) = try await next(authedRequest, body, baseURL)

        // FIX(bug): The original guard `maxRequestAttempts > 1` was always true for the
        // constant value of 2, making the constant meaningless. This loop correctly uses
        // maxRequestAttempts to control retry count: attempt 1 is the initial call above,
        // so we retry at most (maxRequestAttempts - 1) more times.
        var attempt = 1
        while response.status == .unauthorized, attempt < AuthConstants.maxRequestAttempts {
            attempt += 1

            // On failed refresh, return the most recent 401 response to the caller.
            let freshToken: String
            do {
                freshToken = try await self.tokenProvider.token()
            } catch {
                return (response, responseBody)
            }

            // If the token hasn't changed, further retries are pointless.
            guard freshToken != lastToken else {
                return (response, responseBody)
            }
            lastToken = freshToken

            var retryRequest = request
            retryRequest.headerFields[.authorization] = "\(self.scheme) \(freshToken)"
            (response, responseBody) = try await next(retryRequest, body, baseURL)
        }

        return (response, responseBody)
    }
}
