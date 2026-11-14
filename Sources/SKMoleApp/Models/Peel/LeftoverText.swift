// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelCore

/// Plain-English text for the engine's evidence about a leftover file.
enum LeftoverText {
    static func why(_ match: LeftoverMatch) -> String {
        let base: String
        switch match.reason {
        case .bundleIdentifier: base = "Named after the app's bundle identifier."
        case .embeddedBundleIdentifier: base = "Named after a helper bundled inside the app."
        case .applicationGroup: base = "Belongs to an app group the app declares."
        case .bundleIdentifierPrefix: base = "Named with the app's identifier prefix."
        case .name: base = "Named like the app. Only the name ties it to the app, so check it."
        case .teamIdentifier: base = "Written by the same developer (signing team)."
        case .vendorPrefix: base = "Named with the developer's identifier prefix."
        case .namePrefix: base = "Starts with the app's name."
        case .launchdJob: base = "A background job the app installed."
        case .linksToTheApp, .leadsToTheApp: base = "A link that leads into the app."
        case .nativeMessagingHost: base = "A browser extension host that runs the app."
        case .installerReceipt: base = "Listed by the app's installer package."
        case .homebrewReceipt, .leadsIntoItsHomebrewReceipt: base = "Homebrew's record of installing the app."
        case .homebrewCask: base = "Installed by the app's Homebrew cask."
        case .managedByTheApp: base = "Kept up by the app itself."
        case .updaterDownloads: base = "Update downloads the app left behind."
        case .namedByTheApp: base = "Named inside the app's own files."
        case .documentedByItsMaker: base = "The developer documents this as the app's data."
        case .inItsMakersFolder: base = "Inside the developer's own folder."
        }

        var notes: [String] = [base]
        if match.isShared { notes.append("Other apps may use it too, so it is not selected for you.") }
        return notes.joined(separator: " ")
    }

    static func confidence(_ match: LeftoverMatch) -> String {
        switch match.confidence {
        case .certain: "Certain"
        case .likely: "Likely"
        case .possible: "Possible"
        }
    }

    static func heldBack(_ reason: HoldBack) -> String {
        switch reason {
        case .holdsDocuments: "Holds documents, so Warren will not move it."
        case .holdsALibrary: "Holds a photo, music or video library."
        case .holdsKeys: "Holds keys."
        case .holdsAWallet: "Holds a crypto wallet."
        case .holdsAPasswordDatabase: "Holds a password database."
        case .holdsRepository, .inARepository, .trackedByGit: "Sits in a Git repository."
        case .holdsVirtualMachines: "Holds virtual machines."
        case .holdsSimulators: "Holds simulators."
        case .holdsWorkMadeWithTheApp: "Holds work made with the app."
        case .keptByMacOS: "macOS keeps this."
        case .inTheCloud: "Syncs through the cloud."
        case .appIsRunning: "The app is running."
        case .changedRecently, .writtenRecently, .arrivedRecently: "Changed recently, so it may be in use."
        case .holdsAnExclusion: "Holds something you excluded."
        case .beyondTheHelper: "Needs administrator rights, which Warren does not have yet."
        default: humanize(reason.rawValue)
        }
    }

    static func kind(_ kind: SearchLocation.Kind) -> String {
        humanize(kind.rawValue)
    }

    /// `applicationSupport` -> `Application support`.
    static func humanize(_ raw: String) -> String {
        var words = ""
        for character in raw {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(character.lowercased())
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
