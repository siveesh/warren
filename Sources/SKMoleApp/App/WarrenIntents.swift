// SPDX-License-Identifier: GPL-3.0-or-later
import AppIntents
import AppKit

/// The places in Warren a Shortcut or Siri can open. Each maps to the app's own `skmole://section/<name>` link.
enum WarrenDestination: String, AppEnum {
    case dashboard, smartCare, cleanup, storage, uninstaller, orphans, homebrew, developerCleanup, history, optimize, relay

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Warren Section"

    static let caseDisplayRepresentations: [WarrenDestination: DisplayRepresentation] = [
        .dashboard: "Dashboard",
        .smartCare: "Smart Care",
        .cleanup: "Cleanup",
        .storage: "Storage",
        .uninstaller: "Uninstaller",
        .orphans: "Orphans",
        .homebrew: "Homebrew",
        .developerCleanup: "Developer Cleanup",
        .history: "History",
        .optimize: "Optimize",
        .relay: "Relay"
    ]

    var slug: String {
        switch self {
        case .dashboard: "dashboard"
        case .smartCare: "smart-care"
        case .cleanup: "cleanup"
        case .storage: "storage"
        case .uninstaller: "uninstall"
        case .orphans: "orphans"
        case .homebrew: "homebrew"
        case .developerCleanup: "developer-cleanup"
        case .history: "history"
        case .optimize: "optimize"
        case .relay: "relay"
        }
    }
}

struct OpenWarrenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Warren Section"
    static let description = IntentDescription("Opens a section of Warren, such as Cleanup or Homebrew.")
    static let openAppWhenRun = true

    @Parameter(title: "Section")
    var section: WarrenDestination

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$section) in Warren")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "skmole://section/\(section.slug)") {
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}

struct WarrenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenWarrenSectionIntent(),
            phrases: [
                "Open \(\.$section) in \(.applicationName)",
                "Show \(\.$section) in \(.applicationName)"
            ],
            shortTitle: "Open Section",
            systemImageName: "hare"
        )
    }
}
