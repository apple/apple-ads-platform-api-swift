// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

#if CONFIGURATION
import Configuration
import Foundation

extension AppleAdsClient.Configuration {
    /// Create a configuration by reading values from a `ConfigReader`.
    ///
    /// Only supports ``AuthMode/key(teamId:keyId:privateKeyPEM:)``
    /// because custom providers require code.
    ///
    /// ## Configuration keys
    ///
    /// | Key | Type | Required | Description |
    /// | --- | --- | --- | --- |
    /// | `clientId` | String | Yes | Your `SEARCHADS.`-prefixed ID |
    /// | `teamId` | String | Yes | Apple Developer team ID |
    /// | `keyId` | String | Yes | ES256 signing key identifier |
    /// | `privateKeyPEM` | String | Yes | PEM-encoded private key |
    /// | `baseURL` | String | No | API base URL override |
    /// | `authBaseURL` | String | No | Auth endpoint URL override |
    /// | `authTimeout` | Double | No | Token fetch timeout (seconds) |
    ///
    /// - Parameter config: The configuration reader.
    /// - Throws: If any required key is missing or a URL value is malformed.
    public init(config: ConfigReader) throws {
        let clientId = try config.requiredString(forKey: "clientId")
        let teamId = try config.requiredString(forKey: "teamId")
        let keyId = try config.requiredString(forKey: "keyId")
        let privateKeyPEM = try config.requiredString(forKey: "privateKeyPEM", isSecret: true)

        self.init(
            clientId: clientId,
            authMode: .key(teamId: teamId, keyId: keyId, privateKeyPEM: privateKeyPEM),
            baseURL: try config.string(forKey: "baseURL").map { try Self.parseURL($0, forKey: "baseURL") },
            authBaseURL: try config.string(forKey: "authBaseURL").map { try Self.parseURL($0, forKey: "authBaseURL") },
            authTimeout: config.double(forKey: "authTimeout").map { Duration.seconds($0) } ?? .seconds(5)
        )
    }

    /// Parses a URL from a configuration string value, throwing if the string is not a valid URL.
    private static func parseURL(_ string: String, forKey key: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw AppleAdsAuthError.invalidConfiguration("Invalid \(key): \(string)")
        }
        return url
    }
}
#endif
