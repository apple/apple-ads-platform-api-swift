// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import AsyncHTTPClient
import Foundation
internal import NIOCore

/// Fetches OAuth access tokens from the Apple ID token endpoint using the client credentials grant.
internal struct AccessTokenFetcher: Sendable {
    private let authBaseURL: URL
    private let clientId: String
    private let getClientSecret: @Sendable () async throws -> String
    private let httpClient: HTTPClient
    private let timeout: Duration

    /// Creates a token fetcher using a JWT signer (key-based auth).
    internal init(
        authBaseURL: URL = AuthConstants.defaultAuthBaseURL,
        clientId: String,
        teamId: String,
        signer: JWTSigner,
        httpClient: HTTPClient,
        timeout: Duration = .seconds(5)
    ) {
        self.authBaseURL = authBaseURL
        self.clientId = clientId
        self.httpClient = httpClient
        self.timeout = timeout
        self.getClientSecret = {
            let claims = JWTSigner.makeClientSecretClaims(clientId: clientId, teamId: teamId)
            return try signer.sign(claims: claims)
        }
    }

    /// Creates a token fetcher using a custom client secret provider.
    internal init(
        authBaseURL: URL = AuthConstants.defaultAuthBaseURL,
        clientId: String,
        clientSecretProvider: any ClientSecretProvider,
        httpClient: HTTPClient,
        timeout: Duration = .seconds(5)
    ) {
        self.authBaseURL = authBaseURL
        self.clientId = clientId
        self.httpClient = httpClient
        self.timeout = timeout
        self.getClientSecret = { try await clientSecretProvider.clientSecret() }
    }

    /// Fetches a fresh access token from the OAuth endpoint.
    ///
    /// - Returns: A valid access token with expiration metadata.
    /// - Throws: ``AppleAdsAuthError`` with code ``AppleAdsAuthError/Code/tokenFetchFailed``
    ///   on network errors, non-2xx responses, or malformed responses.
    internal func fetch() async throws -> AccessToken {
        let clientSecret: String
        do {
            clientSecret = try await self.getClientSecret()
        } catch {
            throw AppleAdsAuthError.tokenFetchFailed(
                "Failed to generate client secret",
                cause: error
            )
        }

        // Use URLComponents for correct form encoding (handles +, spaces, etc.)
        var formComponents = URLComponents()
        formComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: AuthConstants.grantType),
            URLQueryItem(name: "client_id", value: self.clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "scope", value: AuthConstants.oauthScope),
        ]
        let body = formComponents.percentEncodedQuery ?? ""

        guard
            let url = URL(
                string: AuthConstants.tokenEndpointPath,
                relativeTo: self.authBaseURL
            )
        else {
            throw AppleAdsAuthError.tokenFetchFailed(
                "Invalid auth URL: \(self.authBaseURL)\(AuthConstants.tokenEndpointPath)"
            )
        }

        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        request.body = .bytes(ByteBuffer(string: body))

        let response: HTTPClientResponse
        do {
            response = try await self.httpClient.execute(request, timeout: .nanoseconds(self.timeout.nanoseconds))
        } catch {
            throw AppleAdsAuthError.tokenFetchFailed(
                "Network error while fetching access token",
                cause: error
            )
        }

        let responseBody: Data
        do {
            responseBody = try await Data(
                response.body.collect(upTo: 1024 * 1024)
                    .readableBytesView
            )
        } catch {
            throw AppleAdsAuthError.tokenFetchFailed(
                "Failed to read token response body",
                cause: error
            )
        }

        guard (200..<300).contains(Int(response.status.code)) else {
            let bodyString = String(decoding: responseBody, as: UTF8.self)
            throw AppleAdsAuthError.tokenFetchFailed(
                "Token endpoint returned HTTP \(response.status.code): \(bodyString)"
            )
        }

        let tokenResponse: TokenEndpointResponse
        do {
            tokenResponse = try JSONDecoder()
                .decode(
                    TokenEndpointResponse.self,
                    from: responseBody
                )
        } catch {
            throw AppleAdsAuthError.tokenFetchFailed(
                "Failed to decode token response",
                cause: error
            )
        }

        guard !tokenResponse.accessToken.isEmpty else {
            throw AppleAdsAuthError.tokenFetchFailed(
                "access_token missing from token endpoint response"
            )
        }

        guard tokenResponse.expiresIn > 0 else {
            throw AppleAdsAuthError.tokenFetchFailed(
                "expires_in missing or invalid (got \(tokenResponse.expiresIn))"
            )
        }

        return AccessToken(
            token: tokenResponse.accessToken,
            expiresInSeconds: tokenResponse.expiresIn
        )
    }
}

// MARK: - Token endpoint response

private struct TokenEndpointResponse: Decodable {
    var accessToken: String
    var tokenType: String
    var expiresIn: Int
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}
