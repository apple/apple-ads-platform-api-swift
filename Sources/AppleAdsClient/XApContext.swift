// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

/// A typed representation of the `X-Ap-Context` header value for the Apple Ads API.
///
/// The Apple Ads API requires an `X-Ap-Context` header on most operations to
/// scope the request to a specific ad account. Use this type to construct the
/// header value:
///
/// ```swift
/// let response = try await client.getCampaignsId(
///     path: .init(id: campaignId),
///     headers: .init(xApContext: XApContext(adAccountID: orgId).rawValue)
/// )
/// ```
public struct XApContext: RawRepresentable, Sendable, Hashable {
    /// The encoded header string (for example, `"adAccountId=12345;"`).
    public let rawValue: String

    /// Creates a context header value for the given ad account.
    ///
    /// - Parameter adAccountID: The ad account identifier.
    public init(adAccountID: Int64) {
        self.rawValue = "adAccountId=\(adAccountID);"
    }

    /// Creates a context header value from a raw string.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
