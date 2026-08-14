// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
@testable import AppleAdsClient

@Suite("AccessToken Tests")
struct AccessTokenTests {

    @Test("isExpired returns false for token expiring in the future")
    func notExpired() {
        let token = AccessToken(
            token: "valid",
            expiresAt: ContinuousClock.now + .seconds(3600)
        )
        #expect(!token.isExpired)
    }

    @Test("isExpired returns true for token already past expiresAt")
    func alreadyExpired() {
        let token = AccessToken(
            token: "stale",
            expiresAt: ContinuousClock.now - .seconds(60)
        )
        #expect(token.isExpired)
    }

    @Test("needsRefresh returns false when well before expiry minus buffer")
    func noRefreshNeeded() {
        let token = AccessToken(
            token: "fresh",
            expiresAt: ContinuousClock.now + .seconds(3600)
        )
        #expect(!token.needsRefresh(buffer: .seconds(300)))
    }

    @Test("needsRefresh returns true when within buffer of expiry")
    func withinBuffer() {
        let token = AccessToken(
            token: "almost-stale",
            expiresAt: ContinuousClock.now + .seconds(60)
        )
        #expect(token.needsRefresh(buffer: .seconds(300)))
    }

    @Test("needsRefresh returns true when already expired")
    func expiredNeedsRefresh() {
        let token = AccessToken(
            token: "expired",
            expiresAt: ContinuousClock.now - .seconds(10)
        )
        #expect(token.needsRefresh(buffer: .seconds(300)))
    }

    @Test("init(token:expiresInSeconds:) creates token expiring approximately N seconds from now")
    func expiresInSeconds() {
        let before = ContinuousClock.now
        let token = AccessToken(token: "timed", expiresInSeconds: 1800)
        let after = ContinuousClock.now

        // expiresAt should be between before+1800s and after+1800s
        #expect(token.expiresAt >= before + .seconds(1800))
        #expect(token.expiresAt <= after + .seconds(1800))
    }

    @Test("init(token:expiresAt:) stores the instant correctly")
    func expiresAtStored() {
        let instant = ContinuousClock.now + .seconds(999)
        let token = AccessToken(token: "stored", expiresAt: instant)
        #expect(token.token == "stored")
        #expect(token.expiresAt == instant)
    }
}
