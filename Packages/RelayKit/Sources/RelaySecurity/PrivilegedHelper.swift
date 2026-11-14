import Foundation


/// The fixed, curated set of privileged operations Relay can run with administrator rights.
///
/// This is the cornerstone of Relay's privileged-helper security model: the helper exposes
/// *only* these predefined operations over XPC. It must **never** accept an arbitrary command
/// string or shell — that would turn the helper into a root-level remote shell. Adding a new
/// capability means adding a case here and implementing it explicitly inside the helper.
public enum PrivilegedOperation: String, Codable, Sendable, CaseIterable {
    case flushDNSCache
    case renewDHCPLease
    case repairPermissions
    case restartService
    case mountProtectedPath
    case editProtectedFile

    /// Human-readable description shown in the UI before the user authorizes the action.
    public var summary: String {
        switch self {
        case .flushDNSCache:      return "Flush the system DNS cache"
        case .renewDHCPLease:     return "Renew the primary network DHCP lease"
        case .repairPermissions:  return "Repair file permissions on system directories"
        case .restartService:     return "Restart a launchd system service"
        case .mountProtectedPath: return "Mount a volume at a protected path"
        case .editProtectedFile:  return "Write to a protected system configuration file"
        }
    }

    /// Shell command to run with administrator privileges for operations that have a fixed invocation.
    /// Returns `nil` for parameterized operations (restartService, mountProtectedPath, editProtectedFile)
    /// that require caller-supplied arguments — those should be run as commands with `requiresElevation`.
    public var elevatedShellCommand: String? {
        switch self {
        case .flushDNSCache:
            return "dscacheutil -flushcache && killall -HUP mDNSResponder"
        case .renewDHCPLease:
            return "ipconfig set $(route get default | awk '/interface: /{print $2}') DHCP"
        case .repairPermissions:
            return "diskutil resetUserPermissions / $(id -u)"
        case .restartService, .mountProtectedPath, .editProtectedFile:
            return nil
        }
    }

    /// SF Symbol for display in the privileged-operations grid.
    public var icon: String {
        switch self {
        case .flushDNSCache:      return "globe.badge.chevron.backward"
        case .renewDHCPLease:     return "arrow.triangle.2.circlepath"
        case .repairPermissions:  return "lock.rotation"
        case .restartService:     return "arrow.clockwise.circle"
        case .mountProtectedPath: return "externaldrive.badge.plus"
        case .editProtectedFile:  return "pencil.and.list.clipboard"
        }
    }
}

