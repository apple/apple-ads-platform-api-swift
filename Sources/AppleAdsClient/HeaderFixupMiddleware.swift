// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Decodes percent-encoded header values set by the generated client.
///
/// Workaround for https://github.com/apple/swift-openapi-generator/issues/857 —
/// the runtime incorrectly percent-encodes header parameter values (`=` → `%3D`,
/// `;` → `%3B`). OpenAPI 3.2.0 clarified that headers should NOT be percent-encoded.
/// Remove this middleware once the upstream fix lands in swift-openapi-runtime.
struct HeaderFixupMiddleware: ClientMiddleware, Sendable {
    // swiftlint:disable:next force_unwrapping
    private static let headerFieldName = HTTPField.Name("X-Ap-Context")!

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let encoded = request.headerFields[Self.headerFieldName] {
            request.headerFields[Self.headerFieldName] =
                encoded.removingPercentEncoding ?? encoded
        }
        return try await next(request, body, baseURL)
    }
}
