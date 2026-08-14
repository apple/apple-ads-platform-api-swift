// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import HTTPTypes
import OpenAPIRuntime
import Foundation

/// Middleware that sets the `User-Agent` header on every request.
///
/// Format: `apple-ads-swift/<version>`
package struct UserAgentMiddleware: ClientMiddleware, Sendable {
    private let userAgent: String

    /// - Parameter version: Library version string. Defaults to ``AppleAdsClient/version``.
    package init(version: String = AppleAdsClient.version) {
        self.userAgent = "apple-ads-swift/\(version)"
    }

    /// Intercepts the request to set the User-Agent header.
    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.userAgent] = self.userAgent
        return try await next(request, body, baseURL)
    }
}
