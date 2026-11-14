// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelCore

/// Plain-English text for the engine's refusal reasons.
enum RemovalFailureText {
    static func describe(_ reason: TrashFailure.Reason) -> String {
        switch reason {
        case .guarded(let refusal):
            guard let refusal else { return "Protected by the removal guard." }
            return describe(refusal)
        case .changedSinceScan, .changeNotKnown: return "The item changed since it was scanned. Scan again."
        case .claimedSinceScan: return "An app installed since the scan uses this item."
        case .lastCopy: return "This is the last copy, so it was kept."
        case .notPermitted: return "macOS did not allow this change. Grant Warren Full Disk Access or App Management."
        case .locked: return "The item is locked. Unlock it in Finder first."
        case .needsHelper: return "Removing this needs administrator rights."
        case .historyUnreadable, .historyCannotBeWritten:
            return "Warren cannot read or write its removal history, so nothing is removed until that works."
        case .heldOpen(let programs), .heldOpenByAJob(let programs), .heldByAnotherAccount(let programs),
             .openForAnotherUser(let programs), .heldByABuildTool(let programs), .inUseByMacOS(let programs):
            return "In use by \(programs.joined(separator: ", ")). Quit it first."
        default:
            return "The removal guard refused this item."
        }
    }

    static func describe(_ refusal: GuardRefusal) -> String {
        switch refusal {
        case .exclusionsNotKnown: return "Warren could not read its exclusions list."
        case .excluded: return "You excluded this item."
        case .staysItself: return "This folder always stays."
        case .protectedLocation: return "This is part of macOS or a protected location."
        case .holdsProtectedData: return "It holds protected data such as keychains, keys or wallets."
        case .inTheCloud: return "It syncs through iCloud or another service."
        case .holdsDocuments: return "It holds documents."
        case .holdsALibrary: return "It holds a photo, music or video library."
        case .holdsWorkKeptInACache: return "It holds work an app keeps only in a cache."
        case .couldNotLookInside: return "macOS did not let Warren look inside, so it was kept."
        }
    }
}
