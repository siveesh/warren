// SPDX-License-Identifier: GPL-3.0-or-later
import SKMoleShared
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// Nil until Warren Companion has written its first reading.
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        // Warren Companion reloads the widgets whenever it writes a reading; this is only the fallback.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(5 * 60))))
    }
}

private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

private func bytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
}

private func rate(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) + "/s"
}

private struct WaitingView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(.secondary)
            Text("Waiting for Warren Companion").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

private struct RingGauge: View {
    let value: Double
    let title: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 7)
            Circle().trim(from: 0, to: max(0.01, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(percent(value)).font(.system(.callout, design: .rounded, weight: .bold)).monospacedDigit()
                Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: System pulse

struct PulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Warren", systemImage: "hare.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        RingGauge(value: snapshot.cpuUsage, title: "CPU", tint: .blue)
                        RingGauge(value: snapshot.memoryUsage, title: "Memory", tint: pressureTint(snapshot))
                    }
                    Text("\(bytes(snapshot.diskFreeBytes)) free").font(.caption2).foregroundStyle(.secondary)
                }
            default:
                HStack(spacing: 14) {
                    RingGauge(value: snapshot.cpuUsage, title: "CPU", tint: .blue)
                    RingGauge(value: snapshot.memoryUsage, title: "Memory", tint: pressureTint(snapshot))
                    RingGauge(value: snapshot.diskUsedRatio, title: "Disk", tint: .purple)
                    VStack(alignment: .leading, spacing: 4) {
                        line("arrow.down", rate(snapshot.downloadBytesPerSecond))
                        line("arrow.up", rate(snapshot.uploadBytesPerSecond))
                        if let battery = snapshot.batteryLevel { line("battery.75percent", percent(battery)) }
                        if let name = snapshot.topProcessName { line("flame", name) }
                    }
                    .font(.caption2)
                }
            }
        } else {
            WaitingView()
        }
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).lineLimit(1).foregroundStyle(.secondary)
    }

    private func pressureTint(_ snapshot: WidgetSnapshot) -> Color {
        switch snapshot.memoryPressureLevel {
        case 2: .red
        case 1: .orange
        default: .green
        }
    }
}

struct PulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKinds[0], provider: SnapshotProvider()) { entry in
            PulseWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("System Pulse")
        .description("CPU, memory and disk use, read by Warren Companion.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Storage

struct StorageWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.purple.opacity(0.18), lineWidth: 9)
                    Circle().trim(from: 0, to: max(0.01, min(1, snapshot.diskUsedRatio)))
                        .stroke(snapshot.diskUsedRatio > 0.9 ? Color.red : Color.purple, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(bytes(snapshot.diskFreeBytes)).font(.system(.callout, design: .rounded, weight: .bold)).minimumScaleFactor(0.6)
                        Text("free").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("of \(bytes(snapshot.diskTotalBytes))").font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            WaitingView()
        }
    }
}

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKinds[1], provider: SnapshotProvider()) { entry in
            StorageWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Storage")
        .description("How much space is free on your startup disk.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct WarrenWidgets: WidgetBundle {
    var body: some Widget {
        PulseWidget()
        StorageWidget()
    }
}
