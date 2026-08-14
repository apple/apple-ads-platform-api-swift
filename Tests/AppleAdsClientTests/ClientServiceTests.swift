// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

#if SERVICE_LIFECYCLE
import Testing
import Foundation
import AsyncHTTPClient
import Logging
import OpenAPIAsyncHTTPClient
import ServiceLifecycle
import ServiceLifecycleTestKit
@testable import AppleAdsClient

@Suite("AppleAdsClient Service Tests")
struct ClientServiceTests {

    // `.tokenProvider` auth builds no internal HTTPClient and no
    // CachingTokenProvider, so this exercises only the gracefulShutdown
    // handshake — not `tokenProvider.close()` or `managedHTTPClient.shutdown()`.
    // Those need `.key` auth against a mock token endpoint.
    @Test("Graceful shutdown completes cleanly with .tokenProvider auth")
    func gracefulShutdownTokenProvider() async throws {
        let logger = Logger(label: "test")
        try await withLogger(logger) { _ in
            let service = try await AppleAdsClient(
                configuration: .init(
                    clientId: "test-client",
                    authMode: .tokenProvider(StaticTokenProvider())
                )
            )

            try await testGracefulShutdown { trigger in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await service.run() }
                    trigger.triggerGracefulShutdown()
                    try await group.next()
                }
            }
        }
    }

    @Test("Graceful shutdown completes cleanly with injected transport")
    func gracefulShutdownInjected() async throws {
        let logger = Logger(label: "test")
        try await withLogger(logger) { _ in
            let httpClient = HTTPClient()
            let transport = AsyncHTTPClientTransport(
                configuration: .init(client: httpClient)
            )

            let service = try await AppleAdsClient(
                configuration: .init(
                    clientId: "test-client",
                    authMode: .tokenProvider(StaticTokenProvider())
                ),
                transport: transport
            )

            try await testGracefulShutdown { trigger in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await service.run() }
                    trigger.triggerGracefulShutdown()
                    try await group.next()
                }
            }

            // Caller owns shutdown when transport is injected
            try await httpClient.shutdown()
        }
    }

    @Test("Client property is available immediately after init")
    func clientAvailableAfterInit() async throws {
        let logger = Logger(label: "test")
        try await withLogger(logger) { _ in
            let httpClient = HTTPClient()
            let transport = AsyncHTTPClientTransport(
                configuration: .init(client: httpClient)
            )

            let service = try await AppleAdsClient(
                configuration: .init(
                    clientId: "test-client",
                    authMode: .tokenProvider(StaticTokenProvider())
                ),
                transport: transport
            )

            let mirror = Mirror(reflecting: service.client)
            #expect(String(describing: mirror.subjectType) == "Client")

            try await httpClient.shutdown()
        }
    }
}

// MARK: - Test Helpers

private struct StaticTokenProvider: TokenProvider, Sendable {
    func token() async throws -> String {
        "test-token"
    }
}
#endif
