// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What a Warren feature is doing, which decides where it may look and act. This is scope, not safety: what must
/// never be removed is decided by one place only, the removal engine's guard (`RemovalService`).
enum GuardPurpose {
    case cleanup
    case uninstall
    case analyze
    case storage
    case developerTooling
    case quarantine
}

/// The folders each feature is limited to. Pure and synchronous, so scanners can ask it freely.
struct RemovalScope: Sendable {
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    private func home(_ path: String) -> URL { home.appendingPathComponent(path) }

    private var cleanupRoots: [URL] {
        [
            "Library/Caches", "Library/Containers", "Library/Group Containers", "Library/Logs",
            "Library/Developer/Xcode/DerivedData", "Library/Developer/CoreSimulator/Caches",
            "Library/Caches/com.docker.docker", "Library/Containers/com.docker.docker/Data/log",
            "Library/Containers/com.docker.docker/Data/tmp", "Downloads", "Desktop", "Documents",
            "Library/Caches/Google/Chrome", "Library/Caches/BraveSoftware/Brave-Browser",
            "Library/Caches/Microsoft Edge", "Library/Caches/Firefox", ".Trash", ".npm/_cacache",
            ".gradle/caches", ".pnpm-store", ".cache/yarn",
        ].map(home(_:))
    }

    private var uninstallRoots: [URL] {
        [URL(fileURLWithPath: "/Applications")] + [
            "Applications", "Library/Application Support", "Library/Caches", "Library/Preferences", "Library/Logs",
            "Library/Saved Application State", "Library/Containers", "Library/Group Containers", "Library/WebKit",
            "Library/LaunchAgents", ".Trash",
        ].map(home(_:))
    }

    private var developerToolRoots: [URL] {
        [URL(fileURLWithPath: "/usr/local/lib"), URL(fileURLWithPath: "/opt/homebrew/lib"), home("lib")]
    }

    private var quarantineRoots: [URL] {
        [URL(fileURLWithPath: "/Applications")] + ["Applications", "Downloads", "Desktop", "Documents"].map(home(_:))
    }

    /// Whether `url` lies in a place `purpose` may work in.
    func allows(_ url: URL, purpose: GuardPurpose, profile: CleanupSafetyProfile) -> Bool {
        let normalized = URLPathSafety.standardized(url)
        let path = normalized.path

        switch purpose {
        case .cleanup:
            let roots = profile.includesExtendedRoots
                ? cleanupRoots + CleanupSafetyProfile.extendedRoots(home: home)
                : cleanupRoots
            return roots.contains { URLPathSafety.isDescendant(normalized, of: $0) } && isSupportedCleanupPath(path)
        case .uninstall:
            if path.hasPrefix("/System/Applications") { return false }
            return uninstallRoots.contains { URLPathSafety.isDescendant(normalized, of: $0) }
        case .analyze:
            return FileManager.default.fileExists(atPath: path) && FileManager.default.isReadableFile(atPath: path)
        case .storage:
            guard URLPathSafety.isDescendant(normalized, of: home) else { return false }
            if URLPathSafety.isDescendant(normalized, of: home("Applications")) { return false }
            if normalized.pathExtension.lowercased() == "app" { return false }
            return !normalized.pathComponents.dropLast().contains { $0.lowercased().hasSuffix(".app") }
        case .developerTooling:
            return isSupportedDeveloperToolingPath(normalized)
        case .quarantine:
            guard normalized.pathExtension.lowercased() == "app" else { return false }
            return quarantineRoots.contains { URLPathSafety.isDescendant(normalized, of: $0) }
        }
    }

    private func isSupportedDeveloperToolingPath(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "dylib", url.lastPathComponent.hasPrefix("lib") else { return false }

        let parent = URLPathSafety.standardized(url.deletingLastPathComponent()).path
        guard developerToolRoots.contains(where: { URLPathSafety.standardized($0).path == parent }) else { return false }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    private func isSupportedCleanupPath(_ path: String) -> Bool {
        if path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/") {
            return path.contains("/Library/Caches/")
                || path.contains("/Data/Library/Caches/")
                || path.contains("/Library/Logs/")
                || path.contains("/Data/Library/Logs/")
                || path.contains("/tmp/")
        }

        return true
    }
}
