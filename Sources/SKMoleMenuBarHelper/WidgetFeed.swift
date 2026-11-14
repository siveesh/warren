// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SKMoleShared
import WidgetKit

/// Passes Warren Companion's readings to Warren's widgets, at most once a minute so the widgets stay within the
/// system's reload budget.
final class WidgetFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var lastWrite = Date.distantPast
    private let interval: TimeInterval = 60

    func offer(_ snapshot: MenuBarSnapshot) {
        lock.lock()
        let due = Date().timeIntervalSince(lastWrite) >= interval
        if due { lastWrite = Date() }
        lock.unlock()
        guard due else { return }

        let reading = WidgetSnapshot(
            cpuUsage: snapshot.cpuUsage,
            memoryUsage: snapshot.memoryUsage,
            memoryUsedBytes: snapshot.memoryUsed,
            memoryTotalBytes: snapshot.memoryTotal,
            diskFreeBytes: snapshot.diskFreeBytes,
            diskTotalBytes: snapshot.diskTotalBytes,
            batteryLevel: snapshot.batteryLevel,
            downloadBytesPerSecond: snapshot.downloadRate,
            uploadBytesPerSecond: snapshot.uploadRate,
            memoryPressureLevel: snapshot.memoryPressureLevel,
            topProcessName: snapshot.topProcessName
        )
        if WidgetSnapshotStore.write(reading) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
