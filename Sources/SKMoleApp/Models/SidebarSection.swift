import Foundation

enum SidebarSection: String, CaseIterable, Hashable, Identifiable {
    case dashboard
    case updates
    case homebrew
    case github
    case relay
    case fileIntelligence
    case network
    case processes
    case quarantine
    case orphans
    case intel
    case packages
    case smartCare
    case cleanup
    case uninstall
    case storage
    case optimize
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .updates: "Updates"
        case .homebrew: "Homebrew"
        case .github: "GitHub"
        case .relay: "Relay"
        case .fileIntelligence: "File Intelligence"
        case .network: "Network"
        case .processes: "Processes"
        case .quarantine: "Quarantine"
        case .orphans: "Orphans"
        case .intel: "Intel Software"
        case .packages: "Package Receipts"
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .uninstall: "Uninstaller"
        case .storage: "Storage"
        case .optimize: "Optimize"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .updates: "arrow.triangle.2.circlepath.circle"
        case .homebrew: "cup.and.saucer.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .relay: "chevron.right.2"
        case .fileIntelligence: "doc.text.viewfinder"
        case .network: "network"
        case .processes: "list.bullet.rectangle.portrait"
        case .quarantine: "shield.slash"
        case .orphans: "questionmark.folder"
        case .intel: "cpu"
        case .packages: "shippingbox"
        case .smartCare: "sparkles.rectangle.stack.fill"
        case .cleanup: "sparkles.rectangle.stack"
        case .uninstall: "xmark.app"
        case .storage: "internaldrive"
        case .optimize: "bolt.badge.clock"
        case .history: "clock.arrow.circlepath"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Real-time system health and fast actions"
        case .updates: "Check application, App Store, Homebrew, and GitHub updates"
        case .homebrew: "Manage Homebrew packages, casks, services, and maintenance"
        case .github: "Install and sign in to GitHub CLI and browse your repositories"
        case .relay: "Saved commands, workflows and the command palette"
        case .fileIntelligence: "Use Magika to classify files by content and scan folders recursively"
        case .network: "On-demand process, connection, and remote-host inspection"
        case .processes: "Inspect active processes and safely terminate user-owned work"
        case .quarantine: "Review quarantined apps and clear com.apple.quarantine deliberately"
        case .orphans: "Find leftover app support files from apps that no longer appear installed"
        case .intel: "Apps, plug-ins and tools that still contain Intel code"
        case .packages: "Installer packages macOS remembers, and what they left on disk"
        case .smartCare: "Guided recommendations across cleanup, storage, and health"
        case .cleanup: "Preview reclaimable space before moving items to Trash"
        case .uninstall: "Remove apps and user-domain remnants safely"
        case .storage: "Surface heavy folders and large files"
        case .optimize: "Refresh caches and user-facing system services"
        case .history: "Everything Warren moved to the Trash, with a way back"
        }
    }

    var shortcutKey: Character {
        switch self {
        case .dashboard: "1"
        case .updates: "u"
        case .homebrew: "2"
        case .github: "g"
        case .relay: "r"
        case .fileIntelligence: "f"
        case .network: "3"
        case .processes: "p"
        case .quarantine: "4"
        case .orphans: "5"
        case .intel: "i"
        case .packages: "k"
        case .smartCare: "6"
        case .cleanup: "7"
        case .uninstall: "8"
        case .storage: "9"
        case .optimize: "0"
        case .history: "h"
        }
    }

    init?(urlSlug: String) {
        switch urlSlug {
        case "dashboard":
            self = .dashboard
        case "updates", "update-check", "software-update":
            self = .updates
        case "homebrew", "brew":
            self = .homebrew
        case "github", "gh":
            self = .github
        case "relay", "palette":
            self = .relay
        case "file-intelligence", "file-intel", "magika":
            self = .fileIntelligence
        case "network":
            self = .network
        case "processes", "process-inspector", "activity":
            self = .processes
        case "quarantine":
            self = .quarantine
        case "orphans", "orphan-review", "leftovers":
            self = .orphans
        case "intel", "rosetta":
            self = .intel
        case "packages", "receipts":
            self = .packages
        case "smart-care", "smartcare":
            self = .smartCare
        case "cleanup":
            self = .cleanup
        case "uninstall", "uninstaller":
            self = .uninstall
        case "storage":
            self = .storage
        case "optimize":
            self = .optimize
        case "history", "removals", "undo":
            self = .history
        default:
            return nil
        }
    }
}

/// The collapsible groups the sidebar is divided into.
enum SidebarGroup: String, CaseIterable, Hashable, Identifiable {
    case overview
    case apps
    case storage
    case developer
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .apps: "Apps"
        case .storage: "Storage"
        case .developer: "Developer"
        case .system: "System"
        }
    }

    /// Sections in the order they appear inside the group.
    var sections: [SidebarSection] {
        switch self {
        case .overview: [.dashboard, .smartCare, .updates]
        case .apps: [.uninstall, .orphans, .intel, .packages, .quarantine]
        case .storage: [.cleanup, .storage, .fileIntelligence]
        case .developer: [.homebrew, .github, .relay]
        case .system: [.network, .processes, .optimize, .history]
        }
    }
}

extension SidebarSection {
    var group: SidebarGroup {
        SidebarGroup.allCases.first { $0.sections.contains(self) } ?? .overview
    }
}

/// Which sidebar groups are collapsed and which sections the user hid, kept as comma-separated strings so they
/// can live in `@AppStorage` and survive relaunches.
struct SidebarPreferences: Equatable {
    static let collapsedGroupsKey = "sidebar.collapsedGroups"
    static let hiddenSectionsKey = "sidebar.hiddenSections"

    private(set) var collapsedGroups: Set<SidebarGroup>
    private(set) var hiddenSections: Set<SidebarSection>

    init(collapsedStored: String = "", hiddenStored: String = "") {
        collapsedGroups = Set(collapsedStored.split(separator: ",").compactMap { SidebarGroup(rawValue: String($0)) })
        hiddenSections = Set(hiddenStored.split(separator: ",").compactMap { SidebarSection(rawValue: String($0)) })
    }

    var collapsedStored: String { collapsedGroups.map(\.rawValue).sorted().joined(separator: ",") }
    var hiddenStored: String { hiddenSections.map(\.rawValue).sorted().joined(separator: ",") }

    func isExpanded(_ group: SidebarGroup) -> Bool { !collapsedGroups.contains(group) }

    mutating func setExpanded(_ expanded: Bool, for group: SidebarGroup) {
        if expanded { collapsedGroups.remove(group) } else { collapsedGroups.insert(group) }
    }

    func shows(_ section: SidebarSection) -> Bool { !hiddenSections.contains(section) }

    mutating func setShown(_ shown: Bool, for section: SidebarSection) {
        if shown { hiddenSections.remove(section) } else { hiddenSections.insert(section) }
    }

    /// Sections of a group that should be listed. The selected section stays visible even if hidden, so the
    /// highlighted row never disappears.
    func visibleSections(in group: SidebarGroup, selection: SidebarSection) -> [SidebarSection] {
        group.sections.filter { shows($0) || $0 == selection }
    }
}
