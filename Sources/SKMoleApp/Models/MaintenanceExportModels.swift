import Foundation
import PeelCore
import UniformTypeIdentifiers

enum MaintenanceExportPluginID: String, CaseIterable, Identifiable, Hashable {
    case dryRunJSON
    case overviewMarkdown
    case overviewText
    case focusedStorageJSON
    case networkSnapshotJSON
    case inventoryJSON
    case inventoryCSV
    case inventoryText
    case inventoryBrewfile

    var id: String { rawValue }
}

struct MaintenanceExportPluginDescriptor: Identifiable, Hashable {
    let id: MaintenanceExportPluginID
    let title: String
    let subtitle: String
    let icon: String
    let fileExtension: String
    let contentType: UTType

    var suggestedBaseName: String {
        switch id {
        case .dryRunJSON:
            return "Warren-Dry-Run"
        case .overviewMarkdown:
            return "Warren-Overview"
        case .overviewText:
            return "Warren-Overview"
        case .focusedStorageJSON:
            return "Warren-Storage-Focus"
        case .networkSnapshotJSON:
            return "Warren-Network-Snapshot"
        case .inventoryJSON, .inventoryCSV, .inventoryText:
            return "Warren-App-Inventory"
        case .inventoryBrewfile:
            return "Brewfile"
        }
    }
}

struct MaintenanceExportContext {
    let maintenanceReport: MaintenanceReport
    let focusedStorageNode: StorageNode?
    let storageFocusConfiguration: StorageFocusConfiguration
    let networkReport: NetworkInspectorReport?
    let metrics: SystemMetricSnapshot
    var inventory: Inventory?
}

struct MaintenanceExportDocument {
    let descriptor: MaintenanceExportPluginDescriptor
    let data: Data
}
