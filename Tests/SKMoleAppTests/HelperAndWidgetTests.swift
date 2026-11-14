// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelPrivileged
import SKMoleShared
import Testing
@testable import SKMoleApp

@Suite("Privileged helper and widgets")
struct HelperAndWidgetTests {
    private static var root: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func plistValue(_ file: String, _ key: String) throws -> String {
        let data = try Data(contentsOf: root.appending(path: file))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return try #require(plist?[key] as? String)
    }

    @Test func helperIdentityMatchesWhatTheBundleShips() {
        #expect(HelperIdentity.helperIdentifier == PrivilegedHelperConstants.daemonLabel)
        #expect(HelperIdentity.machServiceName == PrivilegedHelperConstants.daemonLabel)
        #expect(HelperIdentity.launchdPlistName == PrivilegedHelperConstants.plistName)
        #expect(HelperIdentity.appIdentifier == MenuBarHelperConstants.mainAppBundleIdentifier)
    }

    @Test func helperAndExtensionCarryTheAppsVersion() throws {
        let build = try Self.plistValue("Resources/Bundling/Info.plist.template", "CFBundleVersion")
        // The app asks the helper for a build no older than its own, so the helper's embedded plist is never behind.
        #expect(try Self.plistValue("Resources/Bundling/PrivilegedHelper-Info.plist", "CFBundleVersion") == build)
        #expect(try Self.plistValue("Resources/Bundling/Widgets-Info.plist.template", "CFBundleVersion") == build)
        #expect(try Self.plistValue("Resources/Bundling/MenuBarHelper-Info.plist.template", "CFBundleVersion") == build)
    }

    @Test func launchDaemonPlistNamesTheHelperProgram() throws {
        let label = try Self.plistValue("Resources/Bundling/com.siveesh.skmole.privilegedhelper.plist.template", "Label")
        let program = try Self.plistValue("Resources/Bundling/com.siveesh.skmole.privilegedhelper.plist.template", "BundleProgram")
        #expect(label == PrivilegedHelperConstants.daemonLabel)
        #expect(program == PrivilegedHelperConstants.bundleProgram)
    }

    @Test func maintenanceTasksAreTheOnesTheHelperKnows() {
        #expect(Set(PrivilegedMaintenanceTask.allCases.map(\.rawValue)) == ["flushDNSCache", "freePurgeableSpace", "runPeriodicDaily"])
    }

    @Test func widgetSnapshotSurvivesTheFile() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var snapshot = WidgetSnapshot.placeholder
        snapshot.date = Date(timeIntervalSince1970: 1_700_000_000)
        let back = try decoder.decode(WidgetSnapshot.self, from: encoder.encode(snapshot))
        #expect(back == snapshot)
        #expect(snapshot.diskUsedRatio > 0.5 && snapshot.diskUsedRatio < 0.6)
    }

    @Test func widgetAppGroupIsTeamPrefixedAndMatchesTheEntitlements() throws {
        for file in ["Widgets.entitlements", "Companion.entitlements"] {
            let data = try Data(contentsOf: Self.root.appending(path: "Resources/Bundling/\(file)"))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            let groups = plist?["com.apple.security.application-groups"] as? [String]
            #expect(groups == [WidgetSnapshotStore.appGroup])
        }
    }
}

@Suite("Homebrew taps")
@MainActor
struct HomebrewTapsTests {
    @Test func tapNamesAndRemotesAreValidated() {
        #expect(HomebrewTapsLibrary.isValidName("siveesh/tap"))
        #expect(HomebrewTapsLibrary.isValidName("homebrew/cask-fonts"))
        #expect(!HomebrewTapsLibrary.isValidName("--force/tap"))
        #expect(!HomebrewTapsLibrary.isValidName("one"))
        #expect(!HomebrewTapsLibrary.isValidName("a/b/c"))
        #expect(!HomebrewTapsLibrary.isValidName("a b/c"))
        #expect(HomebrewTapsLibrary.isValidRemote("https://github.com/siveesh/homebrew-tap"))
        #expect(HomebrewTapsLibrary.isValidRemote("git@github.com:siveesh/homebrew-tap.git"))
        #expect(!HomebrewTapsLibrary.isValidRemote("--upload-pack=evil"))
        #expect(!HomebrewTapsLibrary.isValidRemote("file:///etc"))
        #expect(!HomebrewTapsLibrary.isValidRemote("https://x y"))
    }

    @Test func tapInfoIsReadThroughWarnings() {
        let output = """
        Warning: something
        [{"name":"amir1376/tap","official":false,"trusted":true,"remote":"https://github.com/amir1376/homebrew-tap",
        "custom_remote":false,"private":false,"formula_names":[],"cask_tokens":["amir1376/tap/ab-download-manager"],
        "branch":"master","last_commit":"3 weeks ago"},{"name":"homebrew/core","official":true}]
        """
        let taps = HomebrewTapsLibrary.parse(output)
        #expect(taps.count == 2)
        #expect(taps[0].trusted && taps[0].packageCount == 1)
        #expect(taps[1].official && !taps[1].trusted && taps[1].remote == nil)
    }
}
