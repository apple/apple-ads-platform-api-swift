// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
import Foundation
import NIOCore
import AsyncHTTPClient
import NIOHTTP1
import NIOPosix
import Synchronization
@testable import AppleAdsClient

/// Tests for AccessTokenFetcher using a local NIO HTTP server as a mock OAuth endpoint.
@Suite("AccessTokenFetcher Tests")
struct AccessTokenFetcherTests {

    /// A test-only EC P-256 private key in PKCS8 format.
    ///
    /// Not a real credential.
    static let fixtureKeyPEM = """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgyPPyZ+aoYSuIiU8t
        WzbxBkkNu4XsZyArpe/g1OORYG6hRANCAAQiV/exhq0psEhDH3y2qGOnH3ELd1Y9
        NzEcnAu0Hm/2r/1av61Bp/fFkEbMQuHYBABDxuY1TSLxPE0eU2sy53rO
        -----END PRIVATE KEY-----
        """

    // MARK: - Helper: run with mock server

    private func withMockServer(
        responseStatus: HTTPResponseStatus,
        responseBody: String,
        captureRequest: CapturedRequest? = nil,
        _ body: (AccessTokenFetcher) async throws -> Void
    ) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline()
                    .flatMap {
                        channel.pipeline.addHandler(
                            MockHandler(
                                responseStatus: responseStatus,
                                responseBody: responseBody,
                                captureRequest: captureRequest
                            )
                        )
                    }
            }
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(host: "127.0.0.1", port: 0)
            .get()

        let port = channel.localAddress!.port!
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))

        let signer = try JWTSigner(pemKey: Self.fixtureKeyPEM, keyID: "test-key")
        let fetcher = AccessTokenFetcher(
            authBaseURL: URL(string: "http://127.0.0.1:\(port)/")!,
            clientId: "test-client",
            teamId: "test-team",
            signer: signer,
            httpClient: httpClient
        )

        var bodyError: (any Error)?
        do {
            try await body(fetcher)
        } catch {
            bodyError = error
        }

        try await httpClient.shutdown()
        try await group.shutdownGracefully()

        if let bodyError {
            throw bodyError
        }
    }

    // MARK: - Success

    @Test("Successful token fetch returns AccessToken")
    func successfulFetch() async throws {
        try await withMockServer(
            responseStatus: .ok,
            responseBody: """
                {"access_token":"test-token-abc","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}
                """
        ) { fetcher in
            let token = try await fetcher.fetch()
            #expect(token.token == "test-token-abc")
            #expect(!token.isExpired)
        }
    }

    @Test("Token fetch sends correct form fields")
    func correctFormFields() async throws {
        let captured = CapturedRequest()
        try await withMockServer(
            responseStatus: .ok,
            responseBody: """
                {"access_token":"t","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}
                """,
            captureRequest: captured
        ) { fetcher in
            _ = try await fetcher.fetch()

            let body = captured.body ?? ""
            #expect(body.contains("grant_type=client_credentials"))
            #expect(body.contains("client_id=test-client"))
            #expect(body.contains("scope=searchadsorg"))
            #expect(captured.contentType == "application/x-www-form-urlencoded")
            #expect(captured.method == "POST")
        }
    }

    // MARK: - Error cases

    @Test("Non-2xx response throws tokenFetchFailed")
    func httpErrorResponse() async throws {
        try await withMockServer(
            responseStatus: .forbidden,
            responseBody: """
                {"error":"access_denied"}
                """
        ) { fetcher in
            do {
                _ = try await fetcher.fetch()
                Issue.record("Should have thrown")
            } catch let error as AppleAdsAuthError {
                #expect(error.code == .tokenFetchFailed)
                #expect(error.message.contains("403"))
                #expect(error.message.contains("access_denied"))
            }
        }
    }

    @Test("Empty access_token throws tokenFetchFailed")
    func emptyAccessToken() async throws {
        try await withMockServer(
            responseStatus: .ok,
            responseBody: """
                {"access_token":"","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}
                """
        ) { fetcher in
            do {
                _ = try await fetcher.fetch()
                Issue.record("Should have thrown")
            } catch let error as AppleAdsAuthError {
                #expect(error.code == .tokenFetchFailed)
                #expect(error.message.contains("access_token missing"))
            }
        }
    }

    @Test("Invalid expires_in throws tokenFetchFailed")
    func invalidExpiresIn() async throws {
        try await withMockServer(
            responseStatus: .ok,
            responseBody: """
                {"access_token":"t","token_type":"Bearer","expires_in":0,"scope":"searchadsorg"}
                """
        ) { fetcher in
            do {
                _ = try await fetcher.fetch()
                Issue.record("Should have thrown")
            } catch let error as AppleAdsAuthError {
                #expect(error.code == .tokenFetchFailed)
                #expect(error.message.contains("expires_in"))
            }
        }
    }

    @Test("Malformed JSON response throws tokenFetchFailed")
    func malformedJSON() async throws {
        try await withMockServer(
            responseStatus: .ok,
            responseBody: "not json at all"
        ) { fetcher in
            do {
                _ = try await fetcher.fetch()
                Issue.record("Should have thrown")
            } catch let error as AppleAdsAuthError {
                #expect(error.code == .tokenFetchFailed)
                #expect(error.message.contains("decode"))
            }
        }
    }

    // MARK: - ClientSecretProvider path

    private func withMockServerUsingProvider(
        responseStatus: HTTPResponseStatus,
        responseBody: String,
        provider: any ClientSecretProvider,
        captureRequest: CapturedRequest? = nil,
        _ body: (AccessTokenFetcher) async throws -> Void
    ) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline()
                    .flatMap {
                        channel.pipeline.addHandler(
                            MockHandler(
                                responseStatus: responseStatus,
                                responseBody: responseBody,
                                captureRequest: captureRequest
                            )
                        )
                    }
            }
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(host: "127.0.0.1", port: 0)
            .get()

        let port = channel.localAddress!.port!
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))

        let fetcher = AccessTokenFetcher(
            authBaseURL: URL(string: "http://127.0.0.1:\(port)/")!,
            clientId: "test-client",
            clientSecretProvider: provider,
            httpClient: httpClient
        )

        var bodyError: (any Error)?
        do {
            try await body(fetcher)
        } catch {
            bodyError = error
        }

        try await httpClient.shutdown()
        try await group.shutdownGracefully()

        if let bodyError {
            throw bodyError
        }
    }

    @Test("Successful token fetch via ClientSecretProvider returns AccessToken")
    func successfulFetchViaProvider() async throws {
        let captured = CapturedRequest()
        let provider = MockClientSecretProvider(secret: "mock-client-secret-jwt")
        try await withMockServerUsingProvider(
            responseStatus: .ok,
            responseBody: """
                {"access_token":"provider-token-xyz","token_type":"Bearer","expires_in":7200,"scope":"searchadsorg"}
                """,
            provider: provider,
            captureRequest: captured
        ) { fetcher in
            let token = try await fetcher.fetch()
            #expect(token.token == "provider-token-xyz")
            #expect(!token.isExpired)
            // The provider's secret must reach the wire verbatim.
            #expect(captured.body?.contains("client_secret=mock-client-secret-jwt") == true)
        }
    }

    @Test("ClientSecretProvider error propagates as tokenFetchFailed")
    func providerErrorPropagates() async throws {
        let provider = MockClientSecretProvider(error: MockProviderError.signingFailed)
        try await withMockServerUsingProvider(
            responseStatus: .ok,
            responseBody: """
                {"access_token":"t","token_type":"Bearer","expires_in":3600,"scope":"searchadsorg"}
                """,
            provider: provider
        ) { fetcher in
            do {
                _ = try await fetcher.fetch()
                Issue.record("Should have thrown")
            } catch let error as AppleAdsAuthError {
                #expect(error.code == .tokenFetchFailed)
                #expect(error.message.contains("client secret"))
                #expect(error.cause is MockProviderError)
            }
        }
    }
}

// MARK: - Mock HTTP Server

private final class CapturedRequest: Sendable {
    private struct Storage: Sendable {
        var body: String?
        var contentType: String?
        var method: String?
    }

    private let storage = Mutex(Storage())

    var body: String? { self.storage.withLock { $0.body } }
    var contentType: String? { self.storage.withLock { $0.contentType } }
    var method: String? { self.storage.withLock { $0.method } }

    func set(body: String, contentType: String?, method: String) {
        self.storage.withLock { s in
            s.body = body
            s.contentType = contentType
            s.method = method
        }
    }
}

private final class MockHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let responseStatus: HTTPResponseStatus
    private let responseBody: String
    private let captureRequest: CapturedRequest?
    private let bodyBuffer = Mutex(ByteBuffer())
    private let headInfo = Mutex<(String?, String)?>(nil)

    init(
        responseStatus: HTTPResponseStatus,
        responseBody: String,
        captureRequest: CapturedRequest?
    ) {
        self.responseStatus = responseStatus
        self.responseBody = responseBody
        self.captureRequest = captureRequest
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = Self.unwrapInboundIn(data)
        switch part {
        case .head(let head):
            self.headInfo.withLock {
                $0 = (head.headers["Content-Type"].first, head.method.rawValue)
            }
        case .body(let buffer):
            self.bodyBuffer.withLock { _ = $0.writeImmutableBuffer(buffer) }
        case .end:
            if let capture = self.captureRequest {
                let bodyString = self.bodyBuffer.withLock { b in
                    String(decoding: b.readableBytesView, as: UTF8.self)
                }
                let info = self.headInfo.withLock { $0 }
                capture.set(body: bodyString, contentType: info?.0, method: info?.1 ?? "")
            }

            var responseBuffer = context.channel.allocator.buffer(
                capacity: self.responseBody.utf8.count
            )
            responseBuffer.writeString(self.responseBody)

            let head = HTTPResponseHead(
                version: .http1_1,
                status: self.responseStatus,
                headers: ["Content-Type": "application/json"]
            )
            context.write(Self.wrapOutboundOut(.head(head)), promise: nil)
            context.write(Self.wrapOutboundOut(.body(.byteBuffer(responseBuffer))), promise: nil)
            context.writeAndFlush(Self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

// MARK: - Mock ClientSecretProvider

private enum MockProviderError: Error {
    case signingFailed
}

private struct MockClientSecretProvider: ClientSecretProvider {
    private let result: Result<String, any Error>

    init(secret: String) {
        self.result = .success(secret)
    }

    init(error: any Error) {
        self.result = .failure(error)
    }

    func clientSecret() async throws -> String {
        try self.result.get()
    }
}
