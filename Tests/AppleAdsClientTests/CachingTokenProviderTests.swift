// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
import Foundation
import Synchronization
@testable import AppleAdsClient

/// Thread-safe counter for use in @Sendable closures.
private final class Counter: Sendable {
    private let _value = Mutex(0)

    var value: Int {
        self._value.withLock { $0 }
    }

    func increment() -> Int {
        self._value.withLock { value in
            value += 1
            return value
        }
    }
}

@Suite("CachingTokenProvider Tests")
struct CachingTokenProviderTests {

    // MARK: - Basic caching behavior

    @Test("Eagerly fetches token on creation")
    func eagerFetch() async throws {
        let counter = Counter()
        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            return AccessToken(token: "token-\(n)", expiresInSeconds: 3600)
        }

        let token = try await provider.token()
        #expect(token == "token-1")
        #expect(counter.value == 1, "Should have fetched exactly once during init")
        await provider.close()
    }

    @Test("Returns cached token without refetching")
    func cacheHit() async throws {
        let counter = Counter()
        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            return AccessToken(token: "cached-\(n)", expiresInSeconds: 3600)
        }

        _ = try await provider.token()
        _ = try await provider.token()
        _ = try await provider.token()

        #expect(counter.value == 1, "Should reuse cached token, not refetch")
        await provider.close()
    }

    @Test("Propagates error from initial fetch")
    func initialFetchError() async {
        do {
            _ = try await CachingTokenProvider {
                throw AppleAdsAuthError.tokenFetchFailed("test error")
            }
            Issue.record("Should have thrown")
        } catch {
            #expect(error is AppleAdsAuthError)
        }
    }

    @Test("close() prevents further scheduling")
    func closeStopsScheduling() async throws {
        let provider = try await CachingTokenProvider {
            AccessToken(token: "t", expiresInSeconds: 3600)
        }

        await provider.close()

        // Should still return cached token after close
        let token = try await provider.token()
        #expect(token == "t")
    }

    // MARK: - Expired token triggers reactive refresh

    @Test("Expired token triggers a fresh fetch on next token() call")
    func expiredTokenRefetches() async throws {
        let counter = Counter()
        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            if n == 1 {
                // Initial token: already expired
                return AccessToken(
                    token: "stale",
                    expiresAt: ContinuousClock.now - .seconds(10)
                )
            }
            return AccessToken(token: "fresh", expiresInSeconds: 3600)
        }

        // The initial fetch returned an expired token, so token() should re-fetch
        let token = try await provider.token()
        #expect(token == "fresh")
        #expect(counter.value == 2)
        await provider.close()
    }

    @Test("Token within expiry buffer triggers a fresh fetch")
    func withinBufferRefetches() async throws {
        let counter = Counter()
        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            if n == 1 {
                // Expires in 30s, but expiryBuffer is 60s → needs refresh
                return AccessToken(
                    token: "almost-stale",
                    expiresAt: ContinuousClock.now + .seconds(30)
                )
            }
            return AccessToken(token: "renewed", expiresInSeconds: 3600)
        }

        let token = try await provider.token()
        #expect(token == "renewed")
        #expect(counter.value == 2)
        await provider.close()
    }

    // MARK: - Concurrent coalescing

    @Test("Concurrent callers share a single in-flight fetch")
    func concurrentCoalescing() async throws {
        let counter = Counter()

        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            if n == 1 {
                // Initial: return expired token so next calls trigger refresh
                return AccessToken(
                    token: "initial",
                    expiresAt: ContinuousClock.now - .seconds(10)
                )
            }
            // The 50ms sleep is load-bearing: it suspends the actor so that
            // concurrent callers can enter token() and find the existing
            // refreshTask to await, exercising the coalescing path.
            try await ContinuousClock().sleep(for: .milliseconds(50))
            return AccessToken(token: "shared-\(n)", expiresInSeconds: 3600)
        }

        // Launch multiple concurrent token() calls
        async let t1 = provider.token()
        async let t2 = provider.token()
        async let t3 = provider.token()

        let results = try await [t1, t2, t3]

        // All should get the same token from the single coalesced fetch
        #expect(results[0] == "shared-2", "Token should come from the refresh path")
        #expect(results.allSatisfy { $0 == "shared-2" })
        // Only one additional fetch beyond the initial
        #expect(counter.value == 2, "Concurrent callers should coalesce into one fetch")
        await provider.close()
    }

    @Test("Concurrent callers all receive the same error when coalesced fetch fails")
    func concurrentCoalescingError() async throws {
        let counter = Counter()

        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            if n == 1 {
                return AccessToken(
                    token: "initial",
                    expiresAt: ContinuousClock.now - .seconds(10)
                )
            }
            // Slow fetch that fails — concurrent callers should all get this error
            try await ContinuousClock().sleep(for: .milliseconds(50))
            throw AppleAdsAuthError.tokenFetchFailed("server unavailable")
        }

        // Launch multiple concurrent token() calls that will all await the same failing fetch
        async let t1: Result<String, any Error> = {
            do { return .success(try await provider.token()) } catch { return .failure(error) }
        }()
        async let t2: Result<String, any Error> = {
            do { return .success(try await provider.token()) } catch { return .failure(error) }
        }()
        async let t3: Result<String, any Error> = {
            do { return .success(try await provider.token()) } catch { return .failure(error) }
        }()

        let results = await [t1, t2, t3]

        // All should receive failures
        for result in results {
            switch result {
            case .success(let token):
                Issue.record("Expected failure but got token: \(token)")
            case .failure(let error):
                let authError = try #require(error as? AppleAdsAuthError)
                #expect(authError.code == .tokenFetchFailed)
            }
        }
        // Only one fetch attempt beyond the initial
        #expect(counter.value == 2, "Concurrent callers should coalesce into one fetch")
        await provider.close()
    }

    // MARK: - Proactive refresh

    @Test("Proactive refresh is scheduled and cancelled by close()")
    func proactiveRefreshCancelledByClose() async throws {
        let counter = Counter()
        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            if n == 1 {
                return AccessToken(
                    token: "short-lived",
                    expiresAt: ContinuousClock.now + .milliseconds(130)
                )
            }
            return AccessToken(token: "refreshed-\(n)", expiresInSeconds: 3600)
        }

        // The proactive refresh delay is max(minRefreshDelay=30s, 130ms - 60s=negative) = 30s.
        // It won't fire during this test, but close() cancels the scheduled task.
        await provider.close()
        #expect(counter.value == 1, "Proactive refresh hasn't fired yet (30s min delay)")

        // NOTE: The proactive refresh path cannot be exercised in a unit test without
        // injecting a clock, because minRefreshDelay is 30s. The refresh() method it
        // calls is the same one tested via expiredTokenRefetches and concurrentCoalescing.
        // TODO: Accept a Clock parameter in CachingTokenProvider for testability.
    }

    // MARK: - Refresh error propagation

    @Test("Refresh error propagates to caller when cached token is expired")
    func refreshErrorPropagates() async throws {
        let counter = Counter()
        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            if n == 1 {
                return AccessToken(
                    token: "will-expire",
                    expiresAt: ContinuousClock.now - .seconds(10)
                )
            }
            throw AppleAdsAuthError.tokenFetchFailed("network down")
        }

        do {
            _ = try await provider.token()
            Issue.record("Should have thrown")
        } catch let error as AppleAdsAuthError {
            #expect(error.code == .tokenFetchFailed)
        }
        await provider.close()
    }

    @Test("After refresh failure, subsequent call retries (no stuck state)")
    func refreshFailureDoesNotStick() async throws {
        let counter = Counter()
        let provider = try await CachingTokenProvider {
            let n = counter.increment()
            switch n {
            case 1:
                return AccessToken(
                    token: "expired",
                    expiresAt: ContinuousClock.now - .seconds(10)
                )
            case 2:
                throw AppleAdsAuthError.tokenFetchFailed("transient")
            default:
                return AccessToken(token: "recovered", expiresInSeconds: 3600)
            }
        }

        // First call: triggers refresh which fails
        do {
            _ = try await provider.token()
            Issue.record("Should have thrown")
        } catch let error as AppleAdsAuthError {
            #expect(error.code == .tokenFetchFailed)
        }

        // Second call: should retry, not return cached error
        let token = try await provider.token()
        #expect(token == "recovered")
        #expect(counter.value == 3)
        await provider.close()
    }
}
