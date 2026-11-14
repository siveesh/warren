// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A size that says how much Warren knows. A folder that could not be read completely is "at least" what was
/// counted, and one that could not be read at all is unknown. Unknown is never shown as zero.
struct MeasuredSize: Equatable, Hashable, Sendable {
    enum State: String, Sendable, Codable {
        case exact
        case atLeast
        case unknown
    }

    var bytes: UInt64
    var state: State

    static func exact(_ bytes: UInt64) -> MeasuredSize { MeasuredSize(bytes: bytes, state: .exact) }
    static func atLeast(_ bytes: UInt64) -> MeasuredSize { MeasuredSize(bytes: bytes, state: .atLeast) }
    static let unknown = MeasuredSize(bytes: 0, state: .unknown)

    var isKnown: Bool { state != .unknown }
    var isExact: Bool { state == .exact }

    /// Sums sizes. Any part that is not exact makes the whole an "at least"; unknown parts add nothing.
    static func + (lhs: MeasuredSize, rhs: MeasuredSize) -> MeasuredSize {
        let exact = lhs.state == .exact && rhs.state == .exact
        return MeasuredSize(bytes: lhs.bytes + rhs.bytes, state: exact ? .exact : .atLeast)
    }

    static func total(_ sizes: some Sequence<MeasuredSize>) -> MeasuredSize {
        sizes.reduce(.exact(0), +)
    }

    var text: String { ByteFormatting.format(self) }
}

extension ByteFormatting {
    static func format(_ size: MeasuredSize) -> String {
        switch size.state {
        case .exact: format(size.bytes)
        case .atLeast: "at least \(format(size.bytes))"
        case .unknown: "unknown"
        }
    }
}
