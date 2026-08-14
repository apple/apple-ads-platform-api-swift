// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Foundation

extension Duration {
    /// Converts to `TimeInterval`, preserving sub-second precision.
    internal var timeInterval: TimeInterval {
        let c = self.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    /// Converts to nanoseconds as `Int64` for NIO timeout APIs.
    internal var nanoseconds: Int64 {
        let c = self.components
        return Int64(c.seconds) * 1_000_000_000 + Int64(c.attoseconds) / 1_000_000_000
    }
}
