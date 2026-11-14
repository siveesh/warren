import RelayAppSupport
import RelayCore
import SwiftUI

/// Hosts Relay's command library, workflows, history and settings inside the main window.
/// The command palette itself lives in the menu bar companion.
struct RelayView: View {
    @ObservedObject var model: AppModel
    @State private var tab: RelayTab = .commands
    @State private var showingHistoryImport = false

    private enum RelayTab: String, CaseIterable, Identifiable {
        case commands = "Commands"
        case workflows = "Workflows"
        case history = "History"
        case settings = "Settings"

        var id: String { rawValue }
    }

    var body: some View {
        let environment = model.relayEnvironment

        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("Relay section", selection: $tab) {
                    ForEach(RelayTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                Spacer()

                if tab == .commands {
                    Button("Import Shell History…") { showingHistoryImport = true }
                        .buttonStyle(.bordered)
                }

                Button("Open Palette") { model.openRelayPalette() }
                    .buttonStyle(.borderedProminent)
                    .help("Opens the command palette from the menu bar companion")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            switch tab {
            case .commands:
                CommandLibraryView(library: environment.library)
            case .workflows:
                TaskLibraryView(taskLibrary: environment.taskLibrary, runCoordinator: environment.runCoordinator)
            case .history:
                HistoryView(history: environment.history)
            case .settings:
                RelaySettingsView(environment: environment)
            }
        }
        .task { await environment.reload() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: RelayShared.didChangeNotification)) { _ in
            Task { await environment.reload() }
        }
        .sheet(isPresented: $showingHistoryImport) {
            HistoryImportView(environment: environment)
        }
    }
}
