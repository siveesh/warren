import Foundation
import Testing
import PeelCore
@testable import SKMoleApp

private func candidate(_ path: String, safety: SafetyLevel) -> CleanupCandidate {
    CleanupCandidate(
        url: URL(fileURLWithPath: path),
        displayName: URL(fileURLWithPath: path).lastPathComponent,
        sizeBytes: 10 * 1_024 * 1_024,
        lastModified: nil,
        rationale: "test",
        safetyLevel: safety
    )
}

@Test func cautiousProfileAlwaysConfirmsAndUsesTrash() {
    let profile = CleanupSafetyProfile.cautious
    let safe = candidate("/Users/test/Library/Caches/com.example", safety: .safe)

    #expect(profile.requiresConfirmation(for: [safe]))
    #expect(!profile.removesPermanently(safe))
    #expect(!profile.requiresConfirmation(for: []))
}

@Test func balancedProfileOnlyConfirmsReviewItems() {
    let profile = CleanupSafetyProfile.balanced
    let safe = candidate("/Users/test/Library/Caches/com.example", safety: .safe)
    let review = candidate("/Users/test/Downloads/big.dmg", safety: .review)

    #expect(!profile.requiresConfirmation(for: [safe]))
    #expect(profile.requiresConfirmation(for: [safe, review]))
    #expect(profile.removesPermanently(safe))
    #expect(!profile.removesPermanently(review))
}

@Test func powerUserProfileNeverConfirmsAndDeletesPermanently() {
    let profile = CleanupSafetyProfile.powerUser
    let review = candidate("/Users/test/Downloads/big.dmg", safety: .review)

    #expect(!profile.requiresConfirmation(for: [review]))
    #expect(profile.removesPermanently(review))
}

@Test func itemsAlreadyInTrashAreRemovedPermanentlyInEveryProfile() {
    let trashed = candidate("/Users/test/.Trash/old.zip", safety: .safe)

    for profile in CleanupSafetyProfile.allCases {
        #expect(profile.removesPermanently(trashed))
    }
}

@Test func relaxedProfilesLowerMinimumSizes() {
    let base: UInt64 = 64 * 1_024 * 1_024

    #expect(CleanupSafetyProfile.cautious.minimumSize(base) == base)
    #expect(CleanupSafetyProfile.balanced.minimumSize(base) == 16 * 1_024 * 1_024)
    #expect(CleanupSafetyProfile.powerUser.minimumSize(base) == 1_024 * 1_024)
    #expect(CleanupSafetyProfile.powerUser.minimumSize(1) == 1)
}

@Test func extendedCleanupRootsOnlyApplyToRelaxedProfiles() async {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let cargo = home.appendingPathComponent(".cargo/registry/cache/index.crate")
    let guardService = RemovalService()

    await guardService.setCleanupProfile(.cautious)
    #expect(await guardService.canOperate(on: cargo, purpose: .cleanup) == false)

    await guardService.setCleanupProfile(.balanced)
    #expect(await guardService.canOperate(on: cargo, purpose: .cleanup))
}

@Test func hardLimitsHoldInEveryProfile() async {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let blocked = [
        URL(fileURLWithPath: "/System/Library/Caches/x"),
        home.appendingPathComponent(".ssh/id_ed25519"),
        home.appendingPathComponent("Library/Keychains/login.keychain-db"),
        home.appendingPathComponent("Library/Mail/V10/x")
    ]
    let guardService = RemovalService()

    for profile in CleanupSafetyProfile.allCases {
        await guardService.setCleanupProfile(profile)
        for url in blocked {
            #expect(await guardService.canOperate(on: url, purpose: .cleanup) == false)
        }
    }
}

@Test func pendingDeletionMessageDescribesTrashAndPermanentSplit() {
    let items = [
        candidate("/Users/test/a", safety: .review),
        candidate("/Users/test/b", safety: .safe)
    ]
    let mixed = PendingCleanupDeletion(candidates: items, permanentCount: 1, trashCount: 1, totalBytes: 20 * 1_024 * 1_024)
    let trashOnly = PendingCleanupDeletion(candidates: items, permanentCount: 0, trashCount: 2, totalBytes: 20 * 1_024 * 1_024)

    #expect(mixed.message.contains("1 will be moved to the Trash and 1 will be deleted permanently"))
    #expect(trashOnly.message.contains("moved to the Trash"))
    #expect(!trashOnly.message.contains("permanently"))
}

@Test func githubAndRelaySectionsResolveFromURLSlugs() {
    #expect(SidebarSection(urlSlug: "github") == .github)
    #expect(SidebarSection(urlSlug: "gh") == .github)
    #expect(SidebarSection(urlSlug: "relay") == .relay)
    #expect(SidebarSection.allCases.map(\.shortcutKey).count == Set(SidebarSection.allCases.map(\.shortcutKey)).count)
}

@Test func masOutdatedOutputYieldsAppStoreIDs() {
    let output = """
    497799835 Xcode (15.0 -> 16.0)
    1295203466 Windows App (11.0 -> 11.1)

    """
    #expect(AppUpdateService.parseOutdatedAdamIDs(output) == [497799835, 1295203466])
    #expect(AppUpdateService.parseOutdatedAdamIDs("").isEmpty)
}

private let sparkleFixture = """
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
<item><title>beta</title><sparkle:channel>beta</sparkle:channel><sparkle:version>125</sparkle:version>
<sparkle:shortVersionString>1.40.2</sparkle:shortVersionString>
<enclosure url="https://example.com/beta.dmg"/>
<sparkle:deltas><enclosure url="https://example.com/d.delta" sparkle:deltaFrom="119"/></sparkle:deltas></item>
<item><title>stable</title><sparkle:version>119</sparkle:version>
<sparkle:shortVersionString>1.40.1</sparkle:shortVersionString>
<enclosure url="https://example.com/stable.dmg"/></item>
<item><title>needs future macOS</title><sparkle:version>200</sparkle:version>
<sparkle:shortVersionString>9.0</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
<enclosure url="https://example.com/future.dmg"/></item>
</channel></rss>
"""

@Test func sparkleParserSkipsBetaChannelAndUnsupportedMacOS() throws {
    let data = Data(sparkleFixture.utf8)
    let stable = try SparkleAppcastParser(baseURL: URL(string: "https://example.com/feed.xml")!).parse(data: data, allowPrerelease: false)
    #expect(stable.latestVersion == "1.40.1")
    #expect(stable.downloadURL?.absoluteString == "https://example.com/stable.dmg")

    let beta = try SparkleAppcastParser(baseURL: URL(string: "https://example.com/feed.xml")!).parse(data: data, allowPrerelease: true)
    #expect(beta.latestVersion == "1.40.2")
    #expect(beta.downloadURL?.absoluteString == "https://example.com/beta.dmg")
}

@Test func prereleaseDetectionRecognizesCommonTags() {
    #expect(AppUpdateService.looksLikePrerelease("0.9.1-beta.144"))
    #expect(!AppUpdateService.looksLikePrerelease("1.40.1"))
    #expect(!AppUpdateService.looksLikePrerelease(nil))
}

@Test @MainActor func permanentlyIgnoredManualReviewItemsMoveToIgnoredList() {
    let item = AppUpdateItem(
        id: "demo-review", kind: .application, displayName: "Demo Review", bundleIdentifier: "com.example.review",
        installedVersion: "1.0", latestVersion: nil, sourceKind: .appStore, status: .manualCheck,
        detail: "Needs a manual check.", sourceDescription: "Mac App Store", appURL: nil, homepageURL: nil,
        primaryURL: nil, primaryURLTitle: nil, secondaryURL: nil, secondaryURLTitle: nil, homebrewReference: nil,
        appStoreAdamID: nil, commandPreview: nil, canAutoInstall: false, releaseNotesSummary: nil,
        releaseNotesURL: nil, releaseNotesURLTitle: nil, fullReleaseNotesURL: nil, fullReleaseNotesURLTitle: nil,
        publishedAt: nil
    )
    let report = AppUpdateReport(
        scannedAt: .now,
        appStoreAutomation: AppStoreAutomationStatus(executablePath: nil, version: nil, accountName: nil, accountDetail: nil),
        scannedApplicationCount: 1, scannedPackageCount: 0, items: [item]
    )
    let store = UpdatesFeatureStore()

    store.rebuild(report: report, searchQuery: "", filter: .attention, ignoredVersions: [:], deferredExpirations: [:])
    #expect(store.filteredManualItems.map(\.id) == [item.id])

    let key = UpdatesFeatureStore.decisionKey(for: item)
    store.rebuild(report: report, searchQuery: "", filter: .attention,
                  ignoredVersions: [key: UpdatesFeatureStore.permanentIgnoreMarker], deferredExpirations: [:])
    #expect(store.filteredManualItems.isEmpty)
    #expect(store.ignoredItems.map(\.id) == [item.id])
}

@Test func everySidebarSectionBelongsToExactlyOneGroup() {
    let grouped = SidebarGroup.allCases.flatMap(\.sections)
    #expect(Set(grouped) == Set(SidebarSection.allCases))
    #expect(grouped.count == SidebarSection.allCases.count)
    #expect(SidebarSection.homebrew.group == .developer)
}

@Test func sidebarPreferencesRoundTripAndKeepSelectionVisible() {
    var preferences = SidebarPreferences()
    #expect(preferences.isExpanded(.storage))

    preferences.setExpanded(false, for: .storage)
    preferences.setShown(false, for: .cleanup)
    let restored = SidebarPreferences(collapsedStored: preferences.collapsedStored, hiddenStored: preferences.hiddenStored)

    #expect(!restored.isExpanded(.storage))
    #expect(restored.isExpanded(.apps))
    #expect(!restored.visibleSections(in: .storage, selection: .dashboard).contains(.cleanup))
    #expect(restored.visibleSections(in: .storage, selection: .cleanup).contains(.cleanup))
}

@Test func leftoverTextHumanizesEngineNames() {
    #expect(LeftoverText.humanize("applicationSupport") == "Application support")
    #expect(LeftoverText.humanize("holdsALibrary") == "Holds a library")
}

@Test func administratorRightsDefaultToAskingEachTime() {
    UserDefaults.standard.removeObject(forKey: AdministratorRights.defaultsKey)
    #expect(AdministratorRights.current == .askEachTime)

    UserDefaults.standard.set(AdministratorRights.never.rawValue, forKey: AdministratorRights.defaultsKey)
    #expect(AdministratorRights.current == .never)
    UserDefaults.standard.removeObject(forKey: AdministratorRights.defaultsKey)
}

@Test func orphanTextNamesEveryConfidenceLevel() {
    #expect(OrphanText.level(.certain) == "Certain")
    #expect(OrphanText.level(.unsure) == "Unsure")
    #expect(OrphanText.reason(.nothingClaimsIt) == "No installed app claims it.")
}

@Test func intelAndPackageSectionsAreWiredIntoTheSidebar() {
    #expect(SidebarSection(urlSlug: "intel") == .intel)
    #expect(SidebarSection(urlSlug: "receipts") == .packages)
    #expect(SidebarSection.intel.group == .apps)
    #expect(SidebarSection.packages.group == .apps)
    #expect(StartupPreference.intel.resolve(lastSelection: nil) == .intel)
    #expect(IntelFinding.Kind.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
}
