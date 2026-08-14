// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
import Foundation
@testable import AppleAdsClient

/// Tests that rewritten open enums (structs) handle unknown server values gracefully.
@Suite("Open Enum Resilience Tests")
struct OpenEnumResilienceTests {

    // MARK: - Unknown values decode without throwing

    @Test("Unknown enum value decodes successfully")
    func unknownValueDecodes() throws {
        let json = Data(#""ARCHIVED""#.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.AuditEventType.self,
                from: json
            )
        #expect(decoded.rawValue == "ARCHIVED")
    }

    @Test("Unknown enum value does not match known cases")
    func unknownValueMismatch() throws {
        let json = Data(#""ARCHIVED""#.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.AuditEventType.self,
                from: json
            )
        #expect(decoded != .create)
        #expect(decoded != .update)
        #expect(decoded != .delete)
    }

    @Test("Known enum value decodes and matches static let")
    func knownValueDecodes() throws {
        let json = Data(#""CREATE""#.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.AuditEventType.self,
                from: json
            )
        #expect(decoded == .create)
        #expect(decoded.rawValue == "CREATE")
    }

    // MARK: - Round-trip encoding

    @Test("Unknown value round-trips through encode/decode")
    func unknownValueRoundTrips() throws {
        let original = Components.Schemas.AuditEventType(rawValue: "FUTURE_VALUE")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.AuditEventType.self,
                from: encoded
            )
        #expect(decoded == original)
        #expect(decoded.rawValue == "FUTURE_VALUE")
    }

    @Test("Known value round-trips through encode/decode")
    func knownValueRoundTrips() throws {
        let original = Components.Schemas.AuditEventType.delete
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.AuditEventType.self,
                from: encoded
            )
        #expect(decoded == original)
        #expect(decoded == .delete)
    }

    // MARK: - Parent object with unknown enum field

    @Test("Parent object decodes when nested enum has unknown value")
    func parentObjectWithUnknownEnum() throws {
        let json = """
            {
                "transactionId": "txn-123",
                "eventType": "MIGRATE"
            }
            """
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.AuditSummary.self,
                from: Data(json.utf8)
            )
        #expect(decoded.transactionId == "txn-123")
        #expect(decoded.eventType?.rawValue == "MIGRATE")
        #expect(decoded.eventType != .create)
        #expect(decoded.eventType != .update)
        #expect(decoded.eventType != .delete)
    }

    @Test("Parent object re-encodes unknown enum value without data loss")
    func parentObjectRoundTripsUnknownEnum() throws {
        let json = """
            {
                "transactionId": "txn-456",
                "eventType": "ROLLBACK"
            }
            """
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.AuditSummary.self,
                from: Data(json.utf8)
            )
        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder()
            .decode(
                Components.Schemas.AuditSummary.self,
                from: reencoded
            )
        #expect(redecoded.eventType?.rawValue == "ROLLBACK")
        #expect(decoded == redecoded)
    }

    // MARK: - allCases excludes unknown values

    @Test("allCases contains only spec-defined values")
    func allCasesIsComplete() {
        let cases = Components.Schemas.AuditEventType.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.create))
        #expect(cases.contains(.update))
        #expect(cases.contains(.delete))
    }
}
