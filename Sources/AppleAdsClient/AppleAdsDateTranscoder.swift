// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Foundation
import OpenAPIRuntime

/// A `DateTranscoder` for the Apple Ads API date format: `yyyy-MM-dd'T'HH:mm:ss.SSS`.
///
/// The server uses this format consistently (no timezone designator) for both
/// requests and responses. This does not conform to RFC 3339 (`format: date-time`
/// in OpenAPI), so swift-openapi-runtime's default ISO8601 transcoder cannot
/// handle it.
struct AppleAdsDateTranscoder: DateTranscoder {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    func encode(_ date: Date) throws -> String {
        Self.formatter.string(from: date)
    }

    func decode(_ dateString: String) throws -> Date {
        guard let date = Self.formatter.date(from: dateString) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription:
                        "Cannot parse date from Apple Ads API. Expected format 'yyyy-MM-dd'T'HH:mm:ss.SSS', got: \(dateString)"
                )
            )
        }
        return date
    }
}
