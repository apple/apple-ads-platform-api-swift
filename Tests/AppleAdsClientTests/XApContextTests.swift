// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
@testable import AppleAdsClient

@Suite("XApContext Tests")
struct XApContextTests {

    @Test("init(adAccountID:) produces correct rawValue format")
    func adAccountIDFormat() {
        let context = XApContext(adAccountID: 12345)
        #expect(context.rawValue == "adAccountId=12345;")
    }

    @Test("init(rawValue:) preserves the raw string exactly")
    func rawValuePreserved() {
        let raw = "orgId=99999;"
        let context = XApContext(rawValue: raw)
        #expect(context.rawValue == raw)
    }

    @Test("RawRepresentable round-trip via Hashable")
    func rawRepresentableRoundTrip() {
        let original = XApContext(adAccountID: 42)
        let roundTripped = XApContext(rawValue: original.rawValue)
        #expect(roundTripped == original)
    }

    @Test("Hashable: two instances with same adAccountID are equal")
    func hashableEqual() {
        let a = XApContext(adAccountID: 7777)
        let b = XApContext(adAccountID: 7777)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Hashable: two instances with different adAccountID are not equal")
    func hashableNotEqual() {
        let a = XApContext(adAccountID: 1)
        let b = XApContext(adAccountID: 2)
        #expect(a != b)
    }

    @Test("Boundary: Int64.max produces valid rawValue")
    func int64Max() {
        let context = XApContext(adAccountID: Int64.max)
        #expect(context.rawValue == "adAccountId=\(Int64.max);")
    }

    @Test("Boundary: zero produces adAccountId=0;")
    func zero() {
        let context = XApContext(adAccountID: 0)
        #expect(context.rawValue == "adAccountId=0;")
    }

    @Test("Boundary: negative value produces correct format")
    func negativeValue() {
        let context = XApContext(adAccountID: -1)
        #expect(context.rawValue == "adAccountId=-1;")
    }
}
