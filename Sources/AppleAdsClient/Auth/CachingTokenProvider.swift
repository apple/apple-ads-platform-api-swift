// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Foundation

/// An actor-based token provider that caches access tokens in memory and
/// proactively refreshes them before expiry.
///
/// - Proactive refresh: scheduled at `expiresIn - 60s` (min 30s delay)
/// - Concurrent coalescing: concurrent callers share a single in-flight fetch
/// - Graceful degradation: proactive refresh failure is reported via callback
internal actor CachingTokenProvider: TokenProvider {
    private var cachedToken: AccessToken?
    private var refreshTask: Task<AccessToken, any Error>?
    private var proactiveRefreshTask: Task<Void, Never>?
    private var isClosed: Bool = false

    private let fetchToken: @Sendable () async throws -> AccessToken
    private let onProactiveRefreshFailure: (@Sendable (any Error) -> Void)?

    /// Creates a caching provider that uses the given closure to fetch tokens.
    ///
    /// The provider eagerly fetches an initial token during creation.
    ///
    /// - Parameters:
    ///   - onProactiveRefreshFailure: Called when background refresh fails.
    ///     The auth module has no swift-log dependency, so logging is delegated to the caller.
    ///   - fetchToken: An async closure that fetches a fresh access token.
    /// - Throws: ``AppleAdsAuthError`` if the initial token fetch fails.
    internal init(
        onProactiveRefreshFailure: (@Sendable (any Error) -> Void)? = nil,
        fetchToken: @escaping @Sendable () async throws -> AccessToken
    ) async throws {
        self.fetchToken = fetchToken
        self.onProactiveRefreshFailure = onProactiveRefreshFailure
        // Eager initial fetch
        // FIX(bug): Use local constant to avoid force-unwrap on the optional property.
        let initialToken = try await fetchToken()
        self.cachedToken = initialToken
        self.scheduleProactiveRefresh(for: initialToken)
    }

    // MARK: - TokenProvider conformance

    /// Returns a cached token if still valid, or fetches a fresh one.
    internal func token() async throws -> String {
        if let cached = self.cachedToken, !cached.needsRefresh(buffer: AuthConstants.expiryBuffer) {
            return cached.token
        }
        return try await self.refresh().token
    }

    /// Cancels proactive refresh scheduling and marks the provider as closed.
    ///
    /// Does not cancel in-flight demand-driven refreshes; callers awaiting
    /// a token will still receive a result.
    internal func close() {
        self.isClosed = true
        self.proactiveRefreshTask?.cancel()
        self.proactiveRefreshTask = nil
    }

    // MARK: - Private

    /// Refreshes the token, coalescing concurrent requests into a single fetch.
    ///
    /// Uses an unstructured `Task` because multiple callers need to
    /// await the same in-flight fetch - this is genuine async isolation that cannot be
    /// expressed with structured concurrency. The task is cleaned up on completion or in `close()`.
    private func refresh() async throws -> AccessToken {
        if let existing = self.refreshTask {
            return try await existing.value
        }

        let task = Task { [fetchToken] in
            try await fetchToken()
        }
        self.refreshTask = task

        do {
            let token = try await task.value
            self.cachedToken = token
            self.refreshTask = nil
            self.scheduleProactiveRefresh(for: token)
            return token
        } catch {
            self.refreshTask = nil
            throw error
        }
    }

    /// Schedules a background refresh before the token expires.
    ///
    /// Delay: `max(minRefreshDelay, expiresIn - expiryBuffer)`
    ///
    /// This uses an unstructured `Task` because the proactive refresh
    /// must outlive any single caller's scope. The task is cancelled in `close()`.
    private func scheduleProactiveRefresh(for token: AccessToken) {
        guard !self.isClosed else { return }

        self.proactiveRefreshTask?.cancel()

        let expiresIn = token.expiresAt - ContinuousClock.now
        let delay = max(AuthConstants.minRefreshDelay, expiresIn - AuthConstants.expiryBuffer)

        self.proactiveRefreshTask = Task {
            try? await ContinuousClock().sleep(for: delay)

            guard !Task.isCancelled else { return }

            do {
                _ = try await self.refresh()
            } catch {
                self.onProactiveRefreshFailure?(error)
            }
        }
    }
}
