// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelCore
import Synchronization

struct GuardedFileIdentity: Equatable, Sendable {
    let volumeIdentifier: String
    let fileIdentifier: String
}

/// The one way Warren removes anything. Peel's `TrashService` is the engine and `RemovalGuard` inside it is the one
/// guard: it decides what is never removed, journals every move for History and Put Back, and checks each item again
/// right before it moves. `RemovalScope` only limits where a feature may look.
final class RemovalService: Sendable {
    let engine: TrashService
    private let scope: RemovalScope
    private let profile = Mutex<CleanupSafetyProfile>(.balanced)

    init(engine: TrashService = TrashService(), scope: RemovalScope = RemovalScope()) {
        self.engine = engine
        self.scope = scope
    }

    func setCleanupProfile(_ newProfile: CleanupSafetyProfile) {
        profile.withLock { $0 = newProfile }
    }

    private var currentProfile: CleanupSafetyProfile { profile.withLock { $0 } }

    /// Why the engine would refuse to remove `url`, or nil when it may go.
    func refusal(of url: URL) -> TrashFailure.Reason? {
        engine.refusal(of: url)
    }

    /// Whether `purpose` may act on `url`: inside the feature's scope and not refused by the engine's guard.
    /// Read-only analysis needs no guard.
    func canOperate(on url: URL, purpose: GuardPurpose) async -> Bool {
        guard scope.allows(url, purpose: purpose, profile: currentProfile) else { return false }
        return purpose == .analyze || engine.refusal(of: url) == nil
    }

    func moveToTrash(_ url: URL, purpose: GuardPurpose) async throws {
        let normalized = url.standardizedFileURL
        guard scope.allows(normalized, purpose: purpose, profile: currentProfile) else {
            throw RemovalError.outsideScope(normalized.path)
        }

        guard FileManager.default.fileExists(atPath: normalized.path) else { return }

        let result = await engine.trash([normalized])
        if let failure = result.failures.first {
            throw RemovalError.refused(RemovalFailureText.describe(failure.reason), normalized.path)
        }
    }

    /// Deletes for good. Used only where the Trash is no option (emptying the Trash itself, or the profile asks
    /// for it): the engine's guard still has to agree, and the item must be the one that was checked.
    func removePermanently(_ url: URL, purpose: GuardPurpose) throws {
        let normalized = url.standardizedFileURL
        guard scope.allows(normalized, purpose: purpose, profile: currentProfile) else {
            throw RemovalError.outsideScope(normalized.path)
        }

        guard FileManager.default.fileExists(atPath: normalized.path) else { return }

        if let reason = engine.refusal(of: normalized) {
            throw RemovalError.refused(RemovalFailureText.describe(reason), normalized.path)
        }

        let values = try normalized.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw RemovalError.symbolicLink(normalized.path) }

        let identity = try Self.fileIdentity(for: normalized)
        try Self.validateStable(normalized, expected: identity)
        try FileManager.default.removeItem(at: normalized)
    }

    /// For changes that are not removals (clearing an attribute): scope plus a fingerprint to compare later.
    func operationIdentity(for url: URL, purpose: GuardPurpose) async throws -> GuardedFileIdentity {
        let normalized = url.standardizedFileURL
        guard scope.allows(normalized, purpose: purpose, profile: currentProfile) else {
            throw RemovalError.outsideScope(normalized.path)
        }

        guard FileManager.default.fileExists(atPath: normalized.path) else { throw RemovalError.gone }
        return try Self.fileIdentity(for: normalized)
    }

    nonisolated func validateStableOperationTarget(_ url: URL, expectedIdentity: GuardedFileIdentity) throws {
        try Self.validateStable(url, expected: expectedIdentity)
    }

    private static func fileIdentity(for url: URL) throws -> GuardedFileIdentity {
        let values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey])
        return GuardedFileIdentity(
            volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) } ?? "volume:unknown",
            fileIdentifier: values.fileResourceIdentifier.map { String(describing: $0) } ?? "file:unknown"
        )
    }

    private static func validateStable(_ url: URL, expected: GuardedFileIdentity) throws {
        guard try fileIdentity(for: url) == expected else { throw RemovalError.changed(url.path) }
    }
}

enum RemovalError: LocalizedError {
    case outsideScope(String)
    case refused(String, String)
    case symbolicLink(String)
    case changed(String)
    case gone

    var errorDescription: String? {
        switch self {
        case .outsideScope(let path): "Warren does not work in this location: \(path)"
        case .refused(let reason, let path): "\(reason) (\(path))"
        case .symbolicLink(let path): "Warren does not delete symbolic links: \(path)"
        case .changed(let path): "Warren stopped because the item changed while it was being checked: \(path)"
        case .gone: "The selected item no longer exists."
        }
    }
}
