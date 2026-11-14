// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The numbers Warren's widgets show. Warren Companion samples them and writes this file; the widgets, which run in
/// their own sandbox, read it from the app group both are signed into.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public var date: Date
    public var cpuUsage: Double
    public var memoryUsage: Double
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var diskFreeBytes: UInt64
    public var diskTotalBytes: UInt64
    public var batteryLevel: Double?
    public var downloadBytesPerSecond: UInt64
    public var uploadBytesPerSecond: UInt64
    /// 0 normal, 1 warning, 2 critical.
    public var memoryPressureLevel: Int
    public var topProcessName: String?

    public init(
        date: Date = .now, cpuUsage: Double, memoryUsage: Double, memoryUsedBytes: UInt64, memoryTotalBytes: UInt64,
        diskFreeBytes: UInt64, diskTotalBytes: UInt64, batteryLevel: Double?, downloadBytesPerSecond: UInt64,
        uploadBytesPerSecond: UInt64, memoryPressureLevel: Int, topProcessName: String?
    ) {
        self.date = date
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.batteryLevel = batteryLevel
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.memoryPressureLevel = memoryPressureLevel
        self.topProcessName = topProcessName
    }

    public var diskUsedRatio: Double {
        diskTotalBytes > 0 ? 1 - Double(diskFreeBytes) / Double(diskTotalBytes) : 0
    }

    public static let placeholder = WidgetSnapshot(
        cpuUsage: 0.23, memoryUsage: 0.58, memoryUsedBytes: 18 << 30, memoryTotalBytes: 32 << 30,
        diskFreeBytes: 420 << 30, diskTotalBytes: 1_000 << 30, batteryLevel: 0.8,
        downloadBytesPerSecond: 1_200_000, uploadBytesPerSecond: 180_000, memoryPressureLevel: 0, topProcessName: "Xcode"
    )
}

public enum WidgetSnapshotStore {
    /// Team-prefixed, so macOS accepts it for a Developer ID app with no provisioning profile.
    public static let appGroup = "MURZTM33SD.com.siveesh.skmole"
    public static let fileName = "widget-snapshot.json"
    public static let widgetKinds = ["com.siveesh.skmole.widget.pulse", "com.siveesh.skmole.widget.storage"]

    public static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
