import Foundation
import Testing
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
    let guardService = SystemGuard()

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
    let guardService = SystemGuard()

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
