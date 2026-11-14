// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelCore

/// Connects Warren's own never-touch rules to the removal engine ported from Peel, so a removal needs both
/// Peel's guard and `SystemGuard` to agree.
enum PeelRemovalGate {
    static func install() {
        ExternalRemovalGate.install { url in
            !SystemGuard.isNeverTouched(url)
        }
    }
}
