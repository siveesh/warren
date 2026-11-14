// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SKMoleShared

/// What Warren will not quit or treat as removable software. Process termination is not a removal, so it is not
/// part of the removal engine.
enum SystemProtection {
    private static let protectedRoots = [
        "/System", "/bin", "/sbin", "/usr", "/private/var/db", "/private/var/root", "/System/Volumes", "/Library/Apple",
    ]

    static func isProtectedApplication(_ url: URL, bundleIdentifier: String?) -> Bool {
        let path = URLPathSafety.standardized(url).path
        return path.hasPrefix("/System/Applications") || (bundleIdentifier?.hasPrefix("com.apple.") ?? false)
    }

    static func canTerminateSnapshot(_ process: NativeProcessActivity) -> Bool {
        guard process.pid > 1, process.pid != getpid(), process.ownerUserID == getuid() else { return false }

        let protectedNames = ["Warren", "Warren Companion", "Finder", "Dock", "System Settings", "Activity Monitor", "loginwindow"]
        if protectedNames.contains(where: { process.name.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
            return false
        }

        let normalized = URLPathSafety.standardized(URL(fileURLWithPath: process.command))
        let path = normalized.path
        if protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }

        let home = FileManager.default.homeDirectoryForCurrentUser
        return path.hasPrefix("/Applications/")
            || URLPathSafety.isDescendant(normalized, of: home)
            || path.hasPrefix("/opt/homebrew/")
            || path.hasPrefix("/usr/local/")
    }
}
