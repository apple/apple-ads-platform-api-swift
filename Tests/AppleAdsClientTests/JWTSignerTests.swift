// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
import Foundation
import Crypto
@testable import AppleAdsClient

@Suite("JWTSigner Tests")
struct JWTSignerTests {
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

    @Test("Signs a JWT with correct three-part structure")
    func jwtStructure() throws {
        let signer = try JWTSigner(pemKey: Self.fixtureKeyPEM, keyID: "test-key-id")
        let claims = JWTSigner.makeClientSecretClaims(clientId: "client-123", teamId: "team-456")
        let jwt = try signer.sign(claims: claims)

        let parts = jwt.split(separator: ".")
        #expect(parts.count == 3, "JWT must have three parts: header.payload.signature")
    }

    @Test("JWT header contains ES256 algorithm and key ID")
    func jwtHeader() throws {
        let signer = try JWTSigner(pemKey: Self.fixtureKeyPEM, keyID: "my-key")
        let claims = JWTSigner.makeClientSecretClaims(clientId: "c", teamId: "t")
        let jwt = try signer.sign(claims: claims)

        let headerPart = String(jwt.split(separator: ".")[0])
        let headerData = Data(base64URLDecoded: headerPart)!
        let header = try JSONDecoder().decode(JWTHeaderCheck.self, from: headerData)

        #expect(header.alg == "ES256")
        #expect(header.typ == "JWT")
        #expect(header.kid == "my-key")
    }

    @Test("JWT claims contain correct sub, iss, aud, and future exp")
    func jwtClaims() throws {
        let signer = try JWTSigner(pemKey: Self.fixtureKeyPEM, keyID: "k")
        let claims = JWTSigner.makeClientSecretClaims(clientId: "my-client", teamId: "my-team")
        let jwt = try signer.sign(claims: claims)

        let payloadPart = String(jwt.split(separator: ".")[1])
        let payloadData = Data(base64URLDecoded: payloadPart)!
        let decoder = JSONDecoder()
        let payload = try decoder.decode(JWTPayloadCheck.self, from: payloadData)

        #expect(payload.sub == "my-client")
        #expect(payload.iss == "my-team")
        #expect(payload.aud == "https://appleid.apple.com")
        #expect(payload.exp > payload.iat, "exp must be after iat")

        // Verify 180-day expiry (within 5 seconds tolerance)
        let expectedExpiry = AuthConstants.clientSecretExpiry.timeInterval
        let actualExpiry = payload.exp - payload.iat
        #expect(abs(actualExpiry - expectedExpiry) < 5.0)
    }

    @Test("Signature uses raw r||s format (64 bytes)")
    func rawSignatureFormat() throws {
        let signer = try JWTSigner(pemKey: Self.fixtureKeyPEM, keyID: "k")
        let claims = JWTSigner.makeClientSecretClaims(clientId: "c", teamId: "t")
        let jwt = try signer.sign(claims: claims)

        let signaturePart = String(jwt.split(separator: ".")[2])
        let signatureData = Data(base64URLDecoded: signaturePart)!

        // ES256 raw representation is exactly 64 bytes (32 bytes r + 32 bytes s)
        #expect(signatureData.count == 64, "ES256 raw signature must be 64 bytes, got \(signatureData.count)")
    }

    @Test("Signature verifies against the public key over header.payload")
    func signatureVerifies() throws {
        let signer = try JWTSigner(pemKey: Self.fixtureKeyPEM, keyID: "k")
        let claims = JWTSigner.makeClientSecretClaims(clientId: "c", teamId: "t")
        let jwt = try signer.sign(claims: claims)

        let parts = jwt.split(separator: ".")
        try #require(parts.count == 3)

        // Catches a signer that hashes the wrong bytes; a length check cannot.
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        let signatureData = try #require(Data(base64URLDecoded: String(parts[2])))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        let publicKey = try P256.Signing
            .PrivateKey(
                pemRepresentation: Self.fixtureKeyPEM
            )
            .publicKey

        #expect(publicKey.isValidSignature(signature, for: SHA256.hash(data: signingInput)))
    }

    @Test("Each signing produces a different JWT (non-deterministic signature)")
    func distinctJWTs() throws {
        // ES256 uses a random nonce per signature, so identical claims still produce different JWTs.
        let signer = try JWTSigner(pemKey: Self.fixtureKeyPEM, keyID: "k")
        let claims = JWTSigner.makeClientSecretClaims(clientId: "c", teamId: "t")
        let jwt1 = try signer.sign(claims: claims)
        let jwt2 = try signer.sign(claims: claims)

        #expect(jwt1 != jwt2)
    }

    @Test("Throws on invalid PEM data")
    func invalidPEMData() throws {
        #expect(throws: AppleAdsAuthError.self) {
            try JWTSigner(pemKey: "not-a-valid-pem-key", keyID: "k")
        }
    }
}

// MARK: - Test helpers

private struct JWTHeaderCheck: Decodable {
    var alg: String
    var typ: String
    var kid: String
}

private struct JWTPayloadCheck: Decodable {
    var sub: String
    var iss: String
    var aud: String
    var iat: Double
    var exp: Double
}

extension Data {
    init?(base64URLDecoded string: String) {
        var base64 =
            string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}
