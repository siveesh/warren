import RelayCore
import SwiftUI
import SKMoleShared

final class MenuBarCompanionContentModel: ObservableObject {
    @Published var snapshot: MenuBarSnapshot?
    @Published var activeAlerts: [MenuBarActiveAlert] = []
    @Published var updateSnapshot: AppUpdateStatusSnapshot?
    @Published var relayQuickRun: [RelayCommand] = []
    @Published var relayCategories: [(category: String, commands: [RelayCommand])] = []
    @Published var relayHotKey = ""
}

private struct PopoverLayoutMetrics {
    let sectionSpacing: CGFloat
    let metricCardHeight: CGFloat
    let topProcessesMinHeight: CGFloat
}

struct MenuBarCompanionPopoverView: View {
    @ObservedObject var model: MenuBarCompanionContentModel
    let openMainApp: () -> Void
    let openUpdates: () -> Void
    let openPalette: () -> Void
    let runRelayCommand: (RelayCommand) -> Void
    let quitCompanion: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]

    var body: some View {
        GeometryReader { proxy in
            if let snapshot = model.snapshot {
                content(snapshot, availableHeight: proxy.size.height)
            } else {
                loadingCard
                    .padding(8)
            }
        }
        .frame(width: 300)
        .background(CompanionPalette.canvas)
    }

    @ViewBuilder
    private func content(_ snapshot: MenuBarSnapshot, availableHeight: CGFloat) -> some View {
        let layout = layoutMetrics(for: availableHeight, showsAlerts: !model.activeAlerts.isEmpty)

        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            hero(snapshot)

            if !model.activeAlerts.isEmpty {
                alertsCard
            }

            metricGrid(snapshot, cardHeight: layout.metricCardHeight)
            topProcessesCard(snapshot, minHeight: layout.topProcessesMinHeight)
            updatesCard
            footerActions
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func layoutMetrics(for availableHeight: CGFloat, showsAlerts: Bool) -> PopoverLayoutMetrics {
        let compactHeight: CGFloat = showsAlerts ? 504 : 466
        let room = max(0, min(1, (availableHeight - compactHeight) / 70))

        return PopoverLayoutMetrics(
            sectionSpacing: 6 + room,
            metricCardHeight: 56 + (room * 12),
            topProcessesMinHeight: 94 + (room * 16)
        )
    }

    private var loadingCard: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Sampling your Mac...")
                .font(.subheadline.weight(.semibold))
            Text("Warren Companion keeps the menu bar light and fills in richer details when opened.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(10)
        .background(panelFill(cornerRadius: 16))
    }

    private func hero(_ snapshot: MenuBarSnapshot) -> some View {
        let score = healthScore(for: snapshot)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: healthSymbol(for: score))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(healthTint(for: score))

                Text("\(score)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(healthTitle(for: score))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button {
                    openMainApp()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help("Open Warren")
            }

            Text(configurationLine(snapshot.systemConfiguration))
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(panelFill(cornerRadius: 17))
    }

    private func configurationLine(_ configuration: MenuBarSystemConfiguration) -> String {
        let device = [configuration.modelName, configuration.chipName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [
            device,
            MenuBarHelperFormatting.formatBytes(configuration.memoryBytes),
            configuration.osVersion,
            configuration.uptime
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(model.activeAlerts.count) alert\(model.activeAlerts.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(CompanionPalette.warning)

            ForEach(model.activeAlerts.prefix(1)) { alert in
                Text(alert.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CompanionPalette.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CompanionPalette.warning.opacity(0.24))
                )
        )
    }

    private func metricGrid(_ snapshot: MenuBarSnapshot, cardHeight: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: 5) {
            metricCard(
                title: "CPU",
                value: percent(snapshot.cpuUsage),
                detail: snapshot.topProcessName ?? "idle",
                systemImage: "cpu",
                tint: CompanionPalette.accent,
                progress: snapshot.cpuUsage,
                minHeight: cardHeight
            )

            metricCard(
                title: "MEM",
                value: percent(snapshot.memoryUsage),
                detail: "\(MenuBarHelperFormatting.formatBytes(snapshot.memoryUsed)) / \(MenuBarHelperFormatting.formatBytes(snapshot.memoryTotal))",
                systemImage: "memorychip",
                tint: CompanionPalette.sand,
                progress: snapshot.memoryUsage,
                minHeight: cardHeight
            )

            metricCard(
                title: "NET",
                value: MenuBarHelperFormatting.formatRate(snapshot.downloadRate),
                detail: "down \(MenuBarHelperFormatting.formatRate(snapshot.downloadRate))  up \(MenuBarHelperFormatting.formatRate(snapshot.uploadRate))",
                systemImage: "network",
                tint: CompanionPalette.sky,
                progress: nil,
                minHeight: cardHeight
            )

            metricCard(
                title: "DISK",
                value: "\(Int(((1 - snapshot.diskFreeRatio) * 100).rounded()))%",
                detail: "\(MenuBarHelperFormatting.formatBytes(snapshot.diskFreeBytes)) free",
                systemImage: "internaldrive",
                tint: CompanionPalette.sky,
                progress: 1 - snapshot.diskFreeRatio,
                minHeight: cardHeight
            )

            metricCard(
                title: "POWER",
                value: snapshot.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "AC",
                detail: snapshot.powerSummary ?? "AC power",
                systemImage: "bolt.fill",
                tint: CompanionPalette.amber,
                progress: snapshot.batteryLevel,
                minHeight: cardHeight
            )

            metricCard(
                title: "THERMAL",
                value: thermalTitle(snapshot.thermalStateLevel),
                detail: "Pressure \(pressureTitle(snapshot.memoryPressureLevel))",
                systemImage: "thermometer.medium",
                tint: thermalTint(snapshot.thermalStateLevel),
                progress: Double(snapshot.thermalStateLevel) / 3,
                minHeight: cardHeight
            )
        }
    }

    private func topProcessesCard(_ snapshot: MenuBarSnapshot, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Top processes", systemImage: "chart.bar.xaxis")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if snapshot.topProcesses.isEmpty {
                Text("Process sampler is warming up.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 3) {
                    processHeader

                    ForEach(snapshot.topProcesses.prefix(4)) { process in
                        processRow(process)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(panelFill(cornerRadius: 13))
    }

    private var updatesCard: some View {
        Button(action: openUpdates) {
            HStack(spacing: 6) {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let updateSnapshot = model.updateSnapshot {
                    Text("\(updateSnapshot.actionableCount) action")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(updateSnapshot.automaticCount) auto")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Open")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(panelFill(cornerRadius: 12))
    }

    private var processHeader: some View {
        HStack {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU")
                .frame(width: 46, alignment: .trailing)
            Text("Memory")
                .frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 8.5, weight: .semibold))
        .foregroundStyle(.tertiary)
    }

    private func processRow(_ process: MenuBarTopProcessSummary) -> some View {
        HStack(spacing: 6) {
            Text(process.name)
                .font(.system(size: 9.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.system(size: 9.5, design: .monospaced))
                .frame(width: 46, alignment: .trailing)

            Text(MenuBarHelperFormatting.formatBytes(process.memoryBytes))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var footerActions: some View {
        VStack(spacing: 6) {
            relayActions
            HStack(spacing: 6) {
                footerButton("Open", systemImage: "circle.grid.2x2", action: openMainApp)
                footerIconButton(systemImage: "power", accessibilityLabel: "Quit Companion", action: quitCompanion)
            }
        }
    }

    private var relayActions: some View {
        HStack(spacing: 6) {
            footerButton(
                model.relayHotKey.isEmpty ? "Palette" : "Palette \(model.relayHotKey)",
                systemImage: "chevron.right.2",
                action: openPalette
            )

            Menu {
                if model.relayQuickRun.isEmpty {
                    Text("No favorites yet - star commands in the palette")
                } else {
                    Section("Favorites") {
                        ForEach(model.relayQuickRun) { command in
                            Button { runRelayCommand(command) } label: {
                                Label(command.name, systemImage: command.icon)
                            }
                        }
                    }
                }

                Divider()

                Menu("All Commands") {
                    ForEach(model.relayCategories, id: \.category) { group in
                        Menu(group.category) {
                            ForEach(group.commands) { command in
                                Button(command.name) { runRelayCommand(command) }
                            }
                        }
                    }
                }
            } label: {
                Label("Favorites", systemImage: "star.circle")
                    .font(.caption2.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CompanionPalette.control)
            )
        }
    }

    private func metricCard(
        title: String,
        value: String,
        detail: String,
        systemImage: String,
        tint: Color,
        progress: Double?,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 8.2, weight: .heavy))
                        .tracking(0.2)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                Text(value)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let progress {
                progressBar(value: progress, tint: tint)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(panelFill(cornerRadius: 12))
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.bold))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CompanionPalette.control)
        )
    }

    private func footerIconButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(width: 34)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CompanionPalette.control)
        )
    }

    private func progressBar(value: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: proxy.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 3)
    }

    private func panelFill(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CompanionPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }

    private func healthScore(for snapshot: MenuBarSnapshot) -> Int {
        var penalty = 0
        penalty += Int(min(35, snapshot.cpuUsage * 28))
        penalty += Int(min(25, snapshot.memoryUsage * 20))
        penalty += snapshot.diskFreeRatio < 0.12 ? 18 : 0
        penalty += snapshot.memoryPressureLevel * 8
        penalty += snapshot.thermalStateLevel * 8
        return max(0, min(100, 100 - penalty))
    }

    private func healthTitle(for score: Int) -> String {
        switch score {
        case 88...100:
            return "Excellent"
        case 70..<88:
            return "Good"
        case 50..<70:
            return "Watch"
        default:
            return "Strained"
        }
    }

    private func healthSymbol(for score: Int) -> String {
        score >= 70 ? "sun.max.fill" : "exclamationmark.triangle.fill"
    }

    private func healthTint(for score: Int) -> Color {
        switch score {
        case 88...100:
            return CompanionPalette.accent
        case 70..<88:
            return CompanionPalette.sky
        case 50..<70:
            return CompanionPalette.amber
        default:
            return CompanionPalette.warning
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func pressureTitle(_ level: Int) -> String {
        SharedMemoryPressureLevel(rawValue: level)?.title ?? "Stable"
    }

    private func thermalTitle(_ level: Int) -> String {
        switch level {
        case 3:
            return "Critical"
        case 2:
            return "Serious"
        case 1:
            return "Fair"
        default:
            return "Nominal"
        }
    }

    private func thermalTint(_ level: Int) -> Color {
        switch level {
        case 2, 3:
            return CompanionPalette.warning
        case 1:
            return CompanionPalette.amber
        default:
            return CompanionPalette.sand
        }
    }
}

private enum CompanionPalette {
    static let accent = Color(red: 0.19, green: 0.78, blue: 0.66)
    static let sky = Color(red: 0.38, green: 0.65, blue: 0.92)
    static let sand = Color(red: 0.86, green: 0.73, blue: 0.49)
    static let amber = Color(red: 0.94, green: 0.66, blue: 0.25)
    static let warning = Color(red: 0.91, green: 0.42, blue: 0.34)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .underPageBackgroundColor).opacity(0.92)
    static let control = Color.primary.opacity(0.07)
}
