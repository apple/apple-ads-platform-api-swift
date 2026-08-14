// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
import Foundation
@testable import AppleAdsClient

@Suite("AppleAdsAuthError Tests")
struct ErrorTests {
    @Test("Error code descriptions are human-readable")
    func codeDescriptions() {
        #expect(String(describing: AppleAdsAuthError.Code.jwtSigningFailed) == "JWT signing failed")
        #expect(String(describing: AppleAdsAuthError.Code.tokenFetchFailed) == "Token fetch failed")
        #expect(String(describing: AppleAdsAuthError.Code.invalidConfiguration) == "Invalid configuration")
    }

    @Test("Error description includes code and message")
    func errorDescription() {
        let error = AppleAdsAuthError.tokenFetchFailed("server returned 500")
        let desc = String(describing: error)
        #expect(desc.contains("tokenFetchFailed"))
        #expect(desc.contains("server returned 500"))
    }

    @Test("Error description includes cause when present")
    func errorWithCause() {
        let underlying = NSError(domain: "test", code: 42)
        let error = AppleAdsAuthError.jwtSigningFailed(
            "key parsing failed",
            cause: underlying
        )
        let desc = String(describing: error)
        #expect(desc.contains("key parsing failed"))
        #expect(desc.contains("42"))
    }

    @Test("Errors with same code and message are equal")
    func equality() {
        let a = AppleAdsAuthError.tokenFetchFailed("fail")
        let b = AppleAdsAuthError.tokenFetchFailed("fail")
        #expect(a == b)
    }

    @Test("Errors with different codes are not equal")
    func inequality() {
        let a = AppleAdsAuthError.tokenFetchFailed("fail")
        let b = AppleAdsAuthError.jwtSigningFailed("fail")
        #expect(a != b)
    }

    @Test("Code is extensible by consumers")
    func extensibility() {
        let custom = AppleAdsAuthError.Code(rawValue: "rateLimited")
        let error = AppleAdsAuthError(code: custom, message: "too many requests")
        #expect(error.code.rawValue == "rateLimited")
        #expect(String(describing: error.code) == "rateLimited")
    }
}
