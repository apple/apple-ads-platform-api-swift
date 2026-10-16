// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Foundation

extension Duration {
    /// Converts to `TimeInterval`, preserving sub-second precision.
    internal var timeInterval: TimeInterval {
        let c = self.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    /// Converts to nanoseconds as `Int64` for NIO timeout APIs.
    ///
    /// Divides `attoseconds` (range [0, 1e18)) by 1e9 first, giving a value in
    /// [0, 1e9) nanoseconds, then adds the seconds-to-nanoseconds term.
    /// This order avoids any intermediate overflow and preserves correct truncation.
    internal var nanoseconds: Int64 {
        let c = self.components
        // FIX(bug): Divide attoseconds before multiplying seconds to keep each
        // intermediate value well within Int64 range ([0, 1e9) and [0, ~9.2e18)).
        let attosecondsNanos = c.attoseconds / 1_000_000_000
        return Int64(c.seconds) * 1_000_000_000 + attosecondsNanos
    }
}
