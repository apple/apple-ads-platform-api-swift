// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

/// A fetched access token with its expiration metadata.
///
/// Uses `ContinuousClock.Instant` (monotonic time) for expiration tracking,
/// making it immune to wall-clock jumps (NTP corrections, DST, user changes).
internal struct AccessToken: Sendable {
    /// The bearer token string.
    internal let token: String

    /// The monotonic instant at which this token expires.
    internal let expiresAt: ContinuousClock.Instant

    /// Whether this token has already expired.
    internal var isExpired: Bool {
        ContinuousClock.now > self.expiresAt
    }

    /// Whether this token should be proactively refreshed given the specified buffer.
    ///
    /// - Parameter buffer: How far before expiration to consider the token stale.
    /// - Returns: `true` if the token should be refreshed.
    internal func needsRefresh(buffer: Duration) -> Bool {
        ContinuousClock.now > self.expiresAt - buffer
    }

    /// Creates an access token from a token string and a monotonic expiration instant.
    ///
    /// - Parameters:
    ///   - token: The bearer token string.
    ///   - expiresAt: The monotonic instant the token expires.
    internal init(token: String, expiresAt: ContinuousClock.Instant) {
        self.token = token
        self.expiresAt = expiresAt
    }

    /// Creates an access token from a token string and an expires-in-seconds value.
    ///
    /// - Parameters:
    ///   - token: The bearer token string.
    ///   - expiresInSeconds: Number of seconds from now until the token expires.
    internal init(token: String, expiresInSeconds: Int) {
        self.token = token
        self.expiresAt = ContinuousClock.now + .seconds(expiresInSeconds)
    }
}
