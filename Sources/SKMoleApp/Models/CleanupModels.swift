import Foundation

enum SafetyLevel: String, CaseIterable, Hashable {
    case safe
    case review
    case protected

    var title: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .protected: "Protected"
        }
    }
}

enum CleanupCategoryID: String, CaseIterable, Identifiable, Hashable {
    case userCaches
    case sandboxCaches
    case browserLeftovers
    case logs
    case developer
    case docker
    case packageManagers
    case toolCaches
    case installers
    case oldDownloads
    case duplicates
    case trash

    var id: String { rawValue }
}

struct CleanupCandidate: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let sizeBytes: UInt64
    let lastModified: Date?
    let rationale: String
    let safetyLevel: SafetyLevel

    var id: String { url.path }
}

struct CleanupCategorySummary: Identifiable, Hashable {
    let category: CleanupCategoryID
    let title: String
    let subtitle: String
    let icon: String
    let safetyLevel: SafetyLevel
    let totalBytes: UInt64
    let candidates: [CleanupCandidate]

    var id: CleanupCategoryID { category }
}

/// User-selectable trade-off between cleanup convenience and caution.
/// Hard limits (system roots, Keychains, Mail, `.ssh`, symlinks, ...) are enforced by
/// `SystemGuard` regardless of the profile.
enum CleanupSafetyProfile: String, CaseIterable, Hashable, Identifiable {
    case cautious
    case balanced
    case powerUser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cautious: "Cautious"
        case .balanced: "Balanced"
        case .powerUser: "Power user"
        }
    }

    var subtitle: String {
        switch self {
        case .cautious:
            "Confirms every cleanup and sends everything to the Trash. Larger items only."
        case .balanced:
            "Confirms only batches that include Review items. Safe caches are removed directly; Review items go to the Trash."
        case .powerUser:
            "No confirmation and permanent removal. Finds smaller items and more developer caches."
        }
    }

    /// Whether a batch needs an explicit confirmation before anything is removed.
    func requiresConfirmation(for candidates: [CleanupCandidate]) -> Bool {
        switch self {
        case .cautious: !candidates.isEmpty
        case .balanced: candidates.contains { $0.safetyLevel != .safe }
        case .powerUser: false
        }
    }

    /// Whether this candidate is deleted for good instead of being moved to the Trash.
    func removesPermanently(_ candidate: CleanupCandidate) -> Bool {
        // Items already in the Trash cannot be trashed again.
        if candidate.url.path.contains("/.Trash/") || candidate.url.lastPathComponent == ".Trash" {
            return true
        }

        switch self {
        case .cautious: return false
        case .balanced: return candidate.safetyLevel == .safe
        case .powerUser: return true
        }
    }

    /// Allows the wider set of developer-tool cache locations in scans and path checks.
    var includesExtendedRoots: Bool { self != .cautious }

    /// Scales a category's default minimum item size down for relaxed profiles.
    func minimumSize(_ base: UInt64) -> UInt64 {
        let floor: UInt64 = 1_024 * 1_024
        switch self {
        case .cautious: return base
        case .balanced: return min(base, max(base / 4, floor))
        case .powerUser: return min(base, floor)
        }
    }

    var duplicateMinimumSize: UInt64 { minimumSize(16 * 1_024 * 1_024) }

    var duplicateSourceLimit: Int {
        switch self {
        case .cautious: 5_000
        case .balanced: 10_000
        case .powerUser: 20_000
        }
    }

    var duplicateResultLimit: Int {
        switch self {
        case .cautious: 48
        case .balanced: 96
        case .powerUser: 200
        }
    }
}

/// A cleanup request waiting for the user's confirmation.
struct PendingCleanupDeletion: Identifiable {
    let id = UUID()
    let candidates: [CleanupCandidate]
    let permanentCount: Int
    let trashCount: Int
    let totalBytes: UInt64

    var message: String {
        let count = candidates.count
        let noun = count == 1 ? "item" : "items"
        let size = ByteFormatting.format(totalBytes)

        switch (trashCount, permanentCount) {
        case (_, 0):
            return "\(count) \(noun) (\(size)) will be moved to the Trash. You can restore them from there."
        case (0, _):
            return "\(count) \(noun) (\(size)) will be deleted permanently. This cannot be undone."
        default:
            return "\(count) \(noun) (\(size)): \(trashCount) will be moved to the Trash and \(permanentCount) will be deleted permanently."
        }
    }
}

extension CleanupSafetyProfile {
    /// Developer-tool cache folders that relaxed profiles may scan and clean.
    static func extendedRoots(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".cache"),
            home.appendingPathComponent(".cargo/registry"),
            home.appendingPathComponent(".cargo/git"),
            home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")
        ]
    }
}
