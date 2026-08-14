// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
import Foundation
import HTTPTypes
import Synchronization
import OpenAPIRuntime
@testable import AppleAdsClient

/// Thread-safe counter for use in @Sendable closures.
private final class CallCounter: Sendable {
    private let _value = Mutex(0)

    var value: Int {
        self._value.withLock { $0 }
    }

    func increment() -> Int {
        self._value.withLock { v in
            v += 1
            return v
        }
    }
}

@Suite("AuthMiddleware Tests")
struct AuthMiddlewareTests {

    @Test("Injects Bearer token into request")
    func injectsBearer() async throws {
        let provider = MockTokenProvider(token: "test-token-123")
        let middleware = AuthMiddleware(tokenProvider: provider)

        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test"),
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let authHeader = request.headerFields[.authorization]
                #expect(authHeader == "Bearer test-token-123")
                return (HTTPResponse(status: .ok), nil)
            }
        )

        #expect(response.status == .ok)
    }

    @Test("Retries once on 401 with fresh token")
    func retriesOn401() async throws {
        let counter = CallCounter()
        let provider = MockTokenProvider(tokens: ["stale-token", "fresh-token"])
        let middleware = AuthMiddleware(tokenProvider: provider)

        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test"),
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let n = counter.increment()
                if n == 1 {
                    return (HTTPResponse(status: .unauthorized), nil)
                }
                let authHeader = request.headerFields[.authorization]
                #expect(authHeader == "Bearer fresh-token")
                return (HTTPResponse(status: .ok), nil)
            }
        )

        #expect(response.status == .ok)
        #expect(counter.value == 2, "Should have made exactly 2 attempts")
    }

    @Test("Does not retry on non-401 errors")
    func noRetryOnOtherErrors() async throws {
        let counter = CallCounter()
        let provider = MockTokenProvider(token: "t")
        let middleware = AuthMiddleware(tokenProvider: provider)

        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test"),
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                _ = counter.increment()
                return (HTTPResponse(status: .forbidden), nil)
            }
        )

        #expect(response.status == .forbidden)
        #expect(counter.value == 1, "Should not retry on 403")
    }

    @Test("Does not retry when refreshed token is identical to stale token")
    func noRetryOnSameToken() async throws {
        let counter = CallCounter()
        let provider = MockTokenProvider(tokens: ["stuck-token"])
        let middleware = AuthMiddleware(tokenProvider: provider)

        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test"),
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                _ = counter.increment()
                return (HTTPResponse(status: .unauthorized), nil)
            }
        )

        #expect(response.status == .unauthorized)
        #expect(counter.value == 1, "Should not retry when the refreshed token is the same as the stale token")
    }

    @Test("Returns 401 when token refresh fails")
    func returns401OnRefreshFailure() async throws {
        let provider = FailingRefreshTokenProvider()
        let middleware = AuthMiddleware(tokenProvider: provider)

        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test"),
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                (HTTPResponse(status: .unauthorized), nil)
            }
        )

        #expect(response.status == .unauthorized)
    }

    @Test("Request body is available on 401 retry")
    func bodyAvailableOnRetry() async throws {
        let counter = CallCounter()
        let provider = MockTokenProvider(tokens: ["stale", "fresh"])
        let middleware = AuthMiddleware(tokenProvider: provider)

        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .post, scheme: "https", authority: "api.example.com", path: "/test"),
            body: HTTPBody("request-payload"),
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let n = counter.increment()
                if n == 1 {
                    // First attempt: consume the body (simulating transport), return 401
                    if let body {
                        _ = try await String(collecting: body, upTo: .max)
                    }
                    return (HTTPResponse(status: .unauthorized), nil)
                }
                // Retry: verify body is still readable after prior consumption
                let bodyString = try await String(collecting: body!, upTo: .max)
                #expect(bodyString == "request-payload")
                return (HTTPResponse(status: .ok), nil)
            }
        )

        #expect(response.status == .ok)
        #expect(counter.value == 2)
    }

    @Test("Stream body throws on retry after consumption")
    func streamBodyFailsOnRetry() async throws {
        let provider = MockTokenProvider(tokens: ["stale", "fresh"])
        let middleware = AuthMiddleware(tokenProvider: provider)

        // Create a one-shot stream-backed body (simulates a streaming upload).
        // This is NOT what the generated OpenAPI client produces (it uses buffer-backed
        // bodies from JSON serialization), but a user could pass one via custom transport.
        let streamBody = HTTPBody(
            AsyncStream<ArraySlice<UInt8>> { continuation in
                continuation.yield(ArraySlice("streamed-data".utf8))
                continuation.finish()
            },
            length: .unknown
        )

        // The middleware passes the same body reference on retry. Stream-backed bodies
        // cannot be iterated twice, so the retry throws.
        await #expect(throws: (any Error).self) {
            _ = try await middleware.intercept(
                HTTPRequest(method: .post, scheme: "https", authority: "api.example.com", path: "/upload"),
                body: streamBody,
                baseURL: URL(string: "https://api.example.com")!,
                operationID: "testOp",
                next: { request, body, url in
                    // Always consume the body and return 401
                    if let body {
                        _ = try await String(collecting: body, upTo: .max)
                    }
                    return (HTTPResponse(status: .unauthorized), nil)
                }
            )
        }
    }

    @Test("Nil body on 401 retry works correctly")
    func nilBodyOnRetry() async throws {
        let counter = CallCounter()
        let provider = MockTokenProvider(tokens: ["stale", "fresh"])
        let middleware = AuthMiddleware(tokenProvider: provider)

        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test"),
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let n = counter.increment()
                if n == 1 {
                    return (HTTPResponse(status: .unauthorized), nil)
                }
                #expect(body == nil)
                return (HTTPResponse(status: .ok), nil)
            }
        )

        #expect(response.status == .ok)
        #expect(counter.value == 2)
    }
}

@Suite("UserAgentMiddleware Tests")
struct UserAgentMiddlewareTests {
    @Test("Sets User-Agent header with explicit version")
    func setsUserAgent() async throws {
        let middleware = UserAgentMiddleware(version: "1.2.3")

        _ = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test"),
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let ua = request.headerFields[.userAgent]
                #expect(ua == "apple-ads-swift/1.2.3")
                return (HTTPResponse(status: .ok), nil)
            }
        )
    }

    @Test("Default version uses libraryVersion constant")
    func defaultVersion() async throws {
        let middleware = UserAgentMiddleware()

        _ = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test"),
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let ua = request.headerFields[.userAgent]
                #expect(ua == "apple-ads-swift/\(AppleAdsClient.version)")
                return (HTTPResponse(status: .ok), nil)
            }
        )
    }
}

@Suite("AppleAdsClient.Configuration Tests")
struct ClientConfigurationTests {
    @Test("Default base URL is nil (resolved to api.ads.apple.com internally)")
    func defaultBaseURL() {
        let config = AppleAdsClient.Configuration(
            clientId: "c",
            authMode: .key(teamId: "t", keyId: "k", privateKeyPEM: "pem")
        )
        #expect(config.baseURL == nil)
    }

    @Test("Default auth timeout is 5 seconds")
    func defaultAuthTimeout() {
        let config = AppleAdsClient.Configuration(
            clientId: "c",
            authMode: .key(teamId: "t", keyId: "k", privateKeyPEM: "pem")
        )
        #expect(config.authTimeout == .seconds(5))
    }

    @Test("AuthMode.key requires all three fields")
    func keyModeRequiresAllFields() {
        // This is enforced at compile time — the static factory parameters
        // require all three. No runtime test needed; this is a compile-time guarantee.
        let mode = AppleAdsClient.Configuration.AuthMode.key(
            teamId: "t",
            keyId: "k",
            privateKeyPEM: "pem"
        )
        if case .key(let teamId, let keyId, let pem) = mode.storage {
            #expect(teamId == "t")
            #expect(keyId == "k")
            #expect(pem == "pem")
        }
    }
}

// MARK: - Mock TokenProvider

private final class MockTokenProvider: TokenProvider, Sendable {
    private struct State: Sendable {
        var tokens: [String]
        var index: Int = 0
    }

    private let state: Mutex<State>

    init(token: String) {
        self.state = Mutex(State(tokens: [token]))
    }

    init(tokens: [String]) {
        self.state = Mutex(State(tokens: tokens))
    }

    func token() async throws -> String {
        self.state.withLock { s in
            let token = s.tokens[min(s.index, s.tokens.count - 1)]
            s.index += 1
            return token
        }
    }
}

/// Mock that always fails on second token() call — for testing 401 fallback behavior.
private final class FailingRefreshTokenProvider: TokenProvider, Sendable {
    private let callCount = Mutex(0)

    func token() async throws -> String {
        let n = callCount.withLock { c in
            c += 1
            return c
        }
        if n == 1 {
            return "initial-token"
        }
        throw AppleAdsAuthError.tokenFetchFailed(
            "Simulated refresh failure"
        )
    }
}

@Suite("HeaderFixupMiddleware Tests")
struct HeaderFixupMiddlewareTests {

    @Test("Percent-encoded X-Ap-Context header is decoded")
    func decodesPercentEncoded() async throws {
        let middleware = HeaderFixupMiddleware()
        var request = HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test")
        request.headerFields[HTTPField.Name("X-Ap-Context")!] = "adAccountId%3D12345%3B"

        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let header = request.headerFields[HTTPField.Name("X-Ap-Context")!]
                #expect(header == "adAccountId=12345;")
                return (HTTPResponse(status: .ok), nil)
            }
        )
    }

    @Test("Already-decoded header passes through unchanged")
    func alreadyDecodedPassthrough() async throws {
        let middleware = HeaderFixupMiddleware()
        var request = HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test")
        request.headerFields[HTTPField.Name("X-Ap-Context")!] = "adAccountId=12345;"

        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let header = request.headerFields[HTTPField.Name("X-Ap-Context")!]
                #expect(header == "adAccountId=12345;")
                return (HTTPResponse(status: .ok), nil)
            }
        )
    }

    @Test("Missing X-Ap-Context header: request passes through without error")
    func missingHeaderPassthrough() async throws {
        let middleware = HeaderFixupMiddleware()
        let request = HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test")

        let (response, _) = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let header = request.headerFields[HTTPField.Name("X-Ap-Context")!]
                #expect(header == nil)
                return (HTTPResponse(status: .ok), nil)
            }
        )

        #expect(response.status == .ok)
    }

    @Test("Other headers are not affected by the middleware")
    func otherHeadersUnaffected() async throws {
        let middleware = HeaderFixupMiddleware()
        var request = HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test")
        request.headerFields[.contentType] = "application/json"
        request.headerFields[HTTPField.Name("X-Ap-Context")!] = "adAccountId%3D12345%3B"

        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                #expect(request.headerFields[.contentType] == "application/json")
                return (HTTPResponse(status: .ok), nil)
            }
        )
    }

    @Test("Invalid percent-encoding falls back to original value")
    func invalidPercentEncodingFallback() async throws {
        let middleware = HeaderFixupMiddleware()
        var request = HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test")
        // "%ZZ" is not a valid percent-encoded sequence; removingPercentEncoding returns nil.
        request.headerFields[HTTPField.Name("X-Ap-Context")!] = "adAccountId%ZZ"

        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let header = request.headerFields[HTTPField.Name("X-Ap-Context")!]
                #expect(header == "adAccountId%ZZ")
                return (HTTPResponse(status: .ok), nil)
            }
        )
    }

    @Test("Response and body are forwarded unchanged")
    func responsePassthrough() async throws {
        let middleware = HeaderFixupMiddleware()
        var request = HTTPRequest(method: .get, scheme: "https", authority: "api.example.com", path: "/test")
        request.headerFields[HTTPField.Name("X-Ap-Context")!] = "adAccountId%3D12345%3B"

        let (response, responseBody) = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                (HTTPResponse(status: .accepted), HTTPBody("payload"))
            }
        )

        #expect(response.status == .accepted)
        let bodyString = try await String(collecting: responseBody!, upTo: .max)
        #expect(bodyString == "payload")
    }

    @Test("Request body is forwarded unchanged")
    func requestBodyPassthrough() async throws {
        let middleware = HeaderFixupMiddleware()
        let request = HTTPRequest(method: .post, scheme: "https", authority: "api.example.com", path: "/test")
        let requestBody = HTTPBody("request-data")

        _ = try await middleware.intercept(
            request,
            body: requestBody,
            baseURL: URL(string: "https://api.example.com")!,
            operationID: "testOp",
            next: { request, body, url in
                let bodyString = try await String(collecting: body!, upTo: .max)
                #expect(bodyString == "request-data")
                return (HTTPResponse(status: .ok), nil)
            }
        )
    }
}
