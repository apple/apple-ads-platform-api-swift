// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import AppleAdsClient

// snippet.hide
@main struct QuickstartSnippet {
    static func main() async throws {
        let pem = ""
        // snippet.show
        try await AppleAdsClient.withClient(
            configuration: .init(
                clientId: "SEARCHADS.your-client-id",
                authMode: .key(
                    teamId: "your-team-id",
                    keyId: "your-key-id",
                    privateKeyPEM: pem
                )
            )
        ) { client in
            let response = try await client.getMe()
            print(response)
        }
        // snippet.hide
    }
}
// snippet.show
