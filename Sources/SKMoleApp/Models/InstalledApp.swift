// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import PeelCore

enum InstalledAppLocation: Hashable {
    case managed
    case trash
}

/// A light view of an installed app for the features that only need a name and a place (updates, orphans,
/// Smart Care). The inventory itself comes from the engine ported from Peel (`AppLibrary`).
struct InstalledApp: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String?
    let url: URL
    let sizeBytes: UInt64
    let isRunning: Bool
    let isProtected: Bool
    let location: InstalledAppLocation

    var id: String { url.path }
    var isInTrash: Bool { location == .trash }
}

extension InstalledApp {
    init(peel app: PeelCore.InstalledApp, location: InstalledAppLocation = .managed) {
        self.init(
            name: app.name,
            bundleIdentifier: app.bundleIdentifier,
            url: app.url,
            sizeBytes: 0,
            isRunning: app.bundleIdentifier.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false,
            isProtected: app.isSystemProtected,
            location: location
        )
    }
}
