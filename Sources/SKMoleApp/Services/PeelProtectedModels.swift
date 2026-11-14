// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelPrivileged

/// The engine's list of protected AI model folders, shared so Warren's scanners skip them before asking the guard.
enum PeelProtectedModels {
    static var folders: [String] { ProtectedData.aiModelFolders }
}
