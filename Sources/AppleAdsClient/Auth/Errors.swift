// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

/// An error from Apple Ads authentication operations.
///
/// Inspect ``code`` for the failure category and ``message`` for
/// details.
public struct AppleAdsAuthError: Error, Sendable, Hashable, CustomStringConvertible {
    /// A high-level classification of the error.
    public let code: Code

    /// A human-readable description of what went wrong.
    public let message: String

    /// The underlying error that caused this failure, if any.
    public let cause: (any Error)?

    /// Creates an authentication error.
    ///
    /// - Parameters:
    ///   - code: The error classification.
    ///   - message: A human-readable description of what went wrong.
    ///   - cause: The underlying error, if any.
    public init(code: Code, message: String, cause: (any Error)? = nil) {
        self.code = code
        self.message = message
        self.cause = cause
    }

    // MARK: - Hashable

    /// Equality compares by ``code`` and ``message`` only.
    ///
    /// The ``cause`` is excluded because `any Error` does not conform to
    /// `Equatable`, and two errors with the same code and message represent
    /// the same logical failure regardless of the underlying cause chain.
    public static func == (lhs: AppleAdsAuthError, rhs: AppleAdsAuthError) -> Bool {
        lhs.code == rhs.code && lhs.message == rhs.message
    }

    /// Hashes the error's code and message.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.code)
        hasher.combine(self.message)
    }

    // MARK: - CustomStringConvertible

    /// A human-readable description of this error.
    public var description: String {
        if let cause = self.cause {
            return "[\(self.code.rawValue)] \(self.message): \(cause)"
        }
        return "[\(self.code.rawValue)] \(self.message)"
    }
}

// MARK: - Error codes

extension AppleAdsAuthError {
    /// A high-level classification of authentication errors.
    public struct Code: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        /// The string representation of this error code.
        public let rawValue: String

        /// Creates an error code from a raw string value.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// JWT creation or signing failed (key parsing, encoding, or ES256 signature).
        public static let jwtSigningFailed = Code(rawValue: "jwtSigningFailed")

        /// Access token fetch from the OAuth endpoint failed.
        public static let tokenFetchFailed = Code(rawValue: "tokenFetchFailed")

        /// Client configuration is invalid (conflicting or missing fields).
        public static let invalidConfiguration = Code(rawValue: "invalidConfiguration")

        /// The string representation of this error code.
        public var description: String {
            switch self.rawValue {
            case "jwtSigningFailed": return "JWT signing failed"
            case "tokenFetchFailed": return "Token fetch failed"
            case "invalidConfiguration": return "Invalid configuration"
            default: return self.rawValue
            }
        }
    }
}

// MARK: - Static factory methods

extension AppleAdsAuthError {
    /// Creates a JWT signing error.
    ///
    /// - Parameters:
    ///   - message: Human-readable description of the signing failure.
    ///   - cause: The underlying error, if any.
    /// - Returns: An ``AppleAdsAuthError`` with code ``Code/jwtSigningFailed``.
    public static func jwtSigningFailed(
        _ message: String,
        cause: (any Error)? = nil
    ) -> Self {
        Self(code: .jwtSigningFailed, message: message, cause: cause)
    }

    /// Creates a token fetch error.
    ///
    /// - Parameters:
    ///   - message: Human-readable description of the fetch failure.
    ///   - cause: The underlying error, if any.
    /// - Returns: An ``AppleAdsAuthError`` with code ``Code/tokenFetchFailed``.
    public static func tokenFetchFailed(
        _ message: String,
        cause: (any Error)? = nil
    ) -> Self {
        Self(code: .tokenFetchFailed, message: message, cause: cause)
    }

    /// Creates an invalid configuration error.
    ///
    /// - Parameters:
    ///   - message: Human-readable description of the configuration problem.
    ///   - cause: The underlying error, if any.
    /// - Returns: An ``AppleAdsAuthError`` with code ``Code/invalidConfiguration``.
    public static func invalidConfiguration(
        _ message: String,
        cause: (any Error)? = nil
    ) -> Self {
        Self(code: .invalidConfiguration, message: message, cause: cause)
    }
}
