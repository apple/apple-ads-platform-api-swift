// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
import Foundation
@testable import AppleAdsClient

/// Model serialization round-trip tests: verify that key OpenAPI-generated types
/// can be deserialized from JSON and re-serialized without data loss.
@Suite("Model Serialization Tests")
struct ModelSerializationTests {

    // MARK: - Error model

    @Test("Error model round-trips through JSON")
    func errorRoundTrip() throws {
        let json = """
            {
                "code": "UNAUTHORIZED",
                "message": "Invalid token",
                "details": []
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas._Error.self,
                from: data
            )
        #expect(decoded.code == "UNAUTHORIZED")
        #expect(decoded.message == "Invalid token")

        // Re-encode and verify no data loss
        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder()
            .decode(
                Components.Schemas._Error.self,
                from: reencoded
            )
        #expect(decoded == redecoded)
    }

    @Test("ErrorDetail model round-trips through JSON")
    func errorDetailRoundTrip() throws {
        let json = """
            {
                "code": "INVALID_FIELD",
                "message": "The field 'name' is required"
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.ErrorDetail.self,
                from: data
            )
        #expect(decoded.code == "INVALID_FIELD")
        #expect(decoded.message == "The field 'name' is required")

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder()
            .decode(
                Components.Schemas.ErrorDetail.self,
                from: reencoded
            )
        #expect(decoded == redecoded)
    }

    // MARK: - Query models

    @Test("QueryRequest model round-trips through JSON")
    func queryRequestRoundTrip() throws {
        let json = """
            {
                "filters": [
                    {
                        "field": "status",
                        "operator": "EQUALS",
                        "value": "ACTIVE"
                    }
                ],
                "sorting": [
                    {
                        "field": "name",
                        "order": "ASC"
                    }
                ]
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryRequest.self,
                from: data
            )
        #expect(decoded.filters?.count == 1)
        #expect(decoded.filters?.first?.field == "status")
        #expect(decoded.filters?.first?._operator == .equals)
        #expect(decoded.filters?.first?.value?.value as? String == "ACTIVE")
        #expect(decoded.sorting?.count == 1)
        #expect(decoded.sorting?.first?.order == .asc)

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryRequest.self,
                from: reencoded
            )
        #expect(decoded == redecoded)
    }

    @Test("QueryPagination model round-trips through JSON")
    func queryPaginationRoundTrip() throws {
        let json = """
            {
                "offset": 100,
                "pageSize": 50
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryPagination.self,
                from: data
            )
        #expect(decoded.offset == 100)
        #expect(decoded.pageSize == 50)

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryPagination.self,
                from: reencoded
            )
        #expect(decoded == redecoded)
    }

    @Test("QueryFilter model round-trips through JSON")
    func queryFilterRoundTrip() throws {
        let json = """
            {
                "field": "country",
                "operator": "IN",
                "value": ["US", "GB", "CA"]
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryFilter.self,
                from: data
            )
        #expect(decoded.field == "country")
        #expect(decoded._operator == ._in)
        #expect(decoded.value?.value as? [String] == ["US", "GB", "CA"])

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryFilter.self,
                from: reencoded
            )
        #expect(decoded == redecoded)
    }

    @Test("QuerySort model round-trips through JSON")
    func querySortRoundTrip() throws {
        let json = """
            {
                "field": "createdAt",
                "order": "DESC"
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.QuerySort.self,
                from: data
            )
        #expect(decoded.field == "createdAt")

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder()
            .decode(
                Components.Schemas.QuerySort.self,
                from: reencoded
            )
        #expect(decoded == redecoded)
    }

    // MARK: - Response wrapper

    @Test("QueryPaginationResult model round-trips through JSON")
    func queryPaginationResultRoundTrip() throws {
        let json = """
            {
                "offset": 0,
                "pageSize": 20,
                "totalCount": 142
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryPaginationResult.self,
                from: data
            )
        #expect(decoded.totalCount == 142)

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryPaginationResult.self,
                from: reencoded
            )
        #expect(decoded == redecoded)
    }

    // MARK: - Empty / minimal payloads

    @Test("QueryRequest with empty body decodes")
    func emptyQueryRequest() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas.QueryRequest.self,
                from: data
            )
        #expect(decoded.filters == nil)
        #expect(decoded.sorting == nil)
    }

    @Test("Error with minimal fields decodes")
    func minimalError() throws {
        let json = """
            {"code": "UNKNOWN"}
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder()
            .decode(
                Components.Schemas._Error.self,
                from: data
            )
        #expect(decoded.code == "UNKNOWN")
        #expect(decoded.message == nil)
        #expect(decoded.details == nil)
    }
}
