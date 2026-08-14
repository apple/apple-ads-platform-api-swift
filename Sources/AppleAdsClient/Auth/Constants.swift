// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Foundation

/// Constants for the Apple Ads OAuth flow.
internal enum AuthConstants {
    /// JWT expiry duration: 180 days.
    internal static let clientSecretExpiry: Duration = .seconds(86_400 * 180)

    /// Default auth base URL.
    internal static let defaultAuthBaseURL: URL = URL(string: "https://appleid.apple.com/")!

    /// How early to trigger proactive refresh before token expiry.
    internal static let expiryBuffer: Duration = .seconds(60)

    /// Minimum delay between token refresh attempts.
    internal static let minRefreshDelay: Duration = .seconds(30)

    /// Maximum total attempts for a request (original + retries on 401).
    internal static let maxRequestAttempts: Int = 2

    // MARK: - Internal (used by client auth flow)

    /// OAuth audience for Apple ID token endpoint.
    internal static let authAudience: String = "https://appleid.apple.com"

    /// OAuth grant type for client credentials flow.
    internal static let grantType: String = "client_credentials"

    /// OAuth scope for Apple Ads.
    internal static let oauthScope: String = "searchadsorg"

    /// Token endpoint path (relative to auth base URL).
    internal static let tokenEndpointPath: String = "auth/oauth2/token"
}
