// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelPrivileged
import SKMoleShared
import Testing

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
