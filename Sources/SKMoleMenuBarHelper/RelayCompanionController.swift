import AppKit
import RelayAppSupport
import RelayCore

/// Hosts Relay inside the menu bar companion: the global hot key, the floating command palette,
/// run progress/result panels, and the Finder Services entry points.
@MainActor
final class RelayCompanionController: NSObject {
    let environment = RelayEnvironment()

    private lazy var palette = PalettePanelController(environment: environment)
    private let resultPanel = ResultPanelController()
    private var hotKey: GlobalHotKey?
    private var changeObserver: NSObjectProtocol?
    private var paletteObserver: NSObjectProtocol?

    /// Human-readable shortcut for the palette, for example "⌥Space".
    var hotKeyDisplay: String { HotKeyPreference.load().displayString }

    func start() {
        Task {
            await environment.reload()
            await environment.notifications.requestAuthorization()
        }

        let coordinator = environment.runCoordinator
        coordinator.onRunningStarted = { [weak self, weak coordinator] name in
            self?.resultPanel.showRunning(name) { coordinator?.cancelCurrent() }
        }
        coordinator.onResult = { [weak self] record in
            self?.resultPanel.show(record)
        }

        registerHotKey()

        // The main app posts this when the shortcut, variables or library change.
        changeObserver = DistributedNotificationCenter.default().addObserver(
            forName: RelayShared.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.registerHotKey()
                await self?.environment.reload()
            }
        }

        paletteObserver = DistributedNotificationCenter.default().addObserver(
            forName: RelayShared.openPaletteNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.palette.show() }
        }

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func togglePalette() {
        palette.toggle()
    }

    /// Favourite commands for one-click running from the popover.
    func favoriteCommands() -> [RelayCommand] {
        environment.library.commands
            .filter(\.favorite)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every command grouped by category, for the "All Commands" submenu.
    func commandsByCategory() -> [(category: String, commands: [RelayCommand])] {
        Dictionary(grouping: environment.library.commands, by: \.category)
            .map { (category: $0.key, commands: $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }

    func run(_ command: RelayCommand) {
        environment.runCoordinator.requestRun(command)
    }

    private func registerHotKey() {
        let preference = HotKeyPreference.load()
        hotKey = nil
        hotKey = GlobalHotKey(keyCode: preference.keyCode, modifiers: preference.modifiers) { [weak self] in
            self?.palette.toggle()
        }
    }

    // MARK: Finder Services (declared in the companion's Info.plist)

    @objc func runWithRelay(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        var query = ""
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            query = urls.map { VariableResolver.shellQuoted($0.path) }.joined(separator: " ")
        } else if let text = pasteboard.string(forType: .string) {
            query = text
        }
        palette.show(withQuery: query)
    }

    @objc func openRelayPalette(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        palette.show()
    }
}
