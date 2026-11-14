import Foundation
import Testing
import PeelCore

/// What Warren's old RemovalService refused outright must also be refused by Peel's guard, the single guard now.
@Test func peelGuardCoversEverythingTheOldWarrenGuardProtected() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let service = TrashService()
    let paths = [
        ".ssh/id_ed25519", ".gnupg/pubring.kbx", ".aws/credentials",
        "Library/Keychains/login.keychain-db", "Library/Mail/V10/x", "Library/Messages/chat.db",
        "Library/Safari/History.db", "Library/Mobile Documents/com~apple~CloudDocs/a",
        "Pictures/Photos Library.photoslibrary/database/x", "Documents/project/.git/config", ".zshrc", ".gitconfig",
    ]
    var unprotected: [String] = []
    for path in paths where service.refusal(of: home.appendingPathComponent(path)) == nil {
        unprotected.append(path)
    }
    #expect(unprotected.isEmpty, "Peel's guard would allow: \(unprotected)")
}
