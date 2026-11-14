// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import PeelCore

/// Builds the inventory of this Mac's apps (where each came from, which version, which architectures) that the
/// export plug-ins write as JSON, CSV or plain text, and Homebrew's Brewfile.
enum InventoryBuilder {
    /// Worked out off the main actor, since it reads every app's download records.
    @concurrent
    static func build(apps: [PeelCore.InstalledApp], casks: [HomebrewPackage], brewfile: String?) async -> Inventory {
        Inventory.build(apps: apps, casks: casks, origins: .onThisMac, brewfile: brewfile)
    }
}

extension MaintenanceExportPluginID {
    var inventoryFormat: Inventory.Format? {
        switch self {
        case .inventoryJSON: .json
        case .inventoryCSV: .csv
        case .inventoryText: .text
        case .inventoryBrewfile: .brewfile
        default: nil
        }
    }
}
