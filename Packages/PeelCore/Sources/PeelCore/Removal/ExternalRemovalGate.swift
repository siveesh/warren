public import Foundation
import Synchronization

/// Warren addition (not in upstream Peel): an extra veto the host app can install. `RemovalGuard` asks it first, so a
/// removal needs both Peel's guard and the host's own rules to agree.
public enum ExternalRemovalGate {
    private static let gate = Mutex<(@Sendable (URL) -> Bool)?>(nil)

    /// Installs the host's rule: it returns false for a path that must never be removed.
    public static func install(_ allows: @escaping @Sendable (URL) -> Bool) {
        gate.withLock { $0 = allows }
    }

    static func allows(_ url: URL) -> Bool {
        gate.withLock { $0?(url) ?? true }
    }
}
