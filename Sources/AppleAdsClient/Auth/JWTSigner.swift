// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Crypto
import Foundation

/// Signs JWTs using ES256 (ECDSA with P-256 and SHA-256) for Apple Ads API authentication.
///
/// Each call to ``sign(claims:)`` produces a fresh JWT. The private key is parsed once
/// at initialization and reused for all subsequent signing operations.
struct JWTSigner: Sendable {
    private let privateKey: P256.Signing.PrivateKey
    private let keyID: String

    /// Creates a signer from a PEM-encoded EC private key string.
    ///
    /// Prefer this initializer over file-path-based initialization to avoid blocking I/O.
    /// The caller is responsible for reading the key file (ideally using async I/O).
    ///
    /// - Parameters:
    ///   - pemKey: The PEM-encoded P-256 private key content (for example, from a .p8 file).
    ///   - keyID: The key identifier from App Store Connect, included in the JWT header.
    /// - Throws: ``AppleAdsAuthError`` if the key cannot be parsed.
    internal init(pemKey: String, keyID: String) throws {
        do {
            self.privateKey = try P256.Signing.PrivateKey(pemRepresentation: pemKey)
        } catch {
            throw AppleAdsAuthError.jwtSigningFailed(
                "Failed to parse EC private key from PEM data",
                cause: error
            )
        }
        self.keyID = keyID
    }

    /// Signs a JWT with the given claims.
    ///
    /// Produces a compact JWT string: `header.payload.signature`.
    /// The signature uses raw `r||s` representation (64 bytes) as required by the JWT spec
    /// for ES256 - not DER encoding.
    ///
    /// - Parameter claims: The JWT claims to sign.
    /// - Returns: A compact JWT string.
    /// - Throws: ``AppleAdsAuthError`` if signing fails.
    internal func sign(claims: Claims) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        let headerData: Data
        let claimsData: Data
        do {
            headerData = try encoder.encode(Header(alg: "ES256", kid: self.keyID))
            claimsData = try encoder.encode(claims)
        } catch {
            throw AppleAdsAuthError.jwtSigningFailed(
                "Failed to encode JWT header or claims",
                cause: error
            )
        }

        let headerEncoded = Self.base64URLEncode(headerData)
        let claimsEncoded = Self.base64URLEncode(claimsData)
        let signingInput = "\(headerEncoded).\(claimsEncoded)"

        let signature: P256.Signing.ECDSASignature
        do {
            let digest = SHA256.hash(data: Data(signingInput.utf8))
            signature = try self.privateKey.signature(for: digest)
        } catch {
            throw AppleAdsAuthError.jwtSigningFailed(
                "ES256 signing failed",
                cause: error
            )
        }

        // JWT ES256 requires raw r||s representation (64 bytes), NOT DER.
        let signatureEncoded = Self.base64URLEncode(Data(signature.rawRepresentation))
        return "\(signingInput).\(signatureEncoded)"
    }

    /// Creates JWT claims for the Apple Ads client credentials flow.
    ///
    /// - Parameters:
    ///   - clientId: The application's client identifier (becomes `sub` claim).
    ///   - teamId: The developer team identifier (becomes `iss` claim).
    /// - Returns: Claims ready for signing.
    internal static func makeClientSecretClaims(
        clientId: String,
        teamId: String
    ) -> Claims {
        Claims(
            issuer: teamId,
            subject: clientId,
            audience: AuthConstants.authAudience,
            issuedAt: Date(),
            expiration: Date().addingTimeInterval(AuthConstants.clientSecretExpiry.timeInterval)
        )
    }

    // MARK: - Private

    /// Encodes data as a base64url string (no padding), per RFC 4648 section 5.
    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Nested types

extension JWTSigner {
    /// JWT claims payload for the Apple Ads OAuth flow.
    internal struct Claims: Sendable, Encodable {
        /// The issuer (team ID).
        internal let issuer: String
        /// The subject (client ID).
        internal let subject: String
        /// The audience (Apple ID endpoint).
        internal let audience: String
        /// The issued-at time.
        internal let issuedAt: Date
        /// The expiration time.
        internal let expiration: Date

        private enum CodingKeys: String, CodingKey {
            case issuer = "iss"
            case subject = "sub"
            case audience = "aud"
            case issuedAt = "iat"
            case expiration = "exp"
        }

    }

    /// JWT header for ES256.
    ///
    /// Includes `typ: "JWT"` per RFC 7519 section 5.1 (RECOMMENDED).
    struct Header: Encodable {
        var alg: String
        var typ: String = "JWT"
        var kid: String
    }
}
