import Foundation
import RelayCore
import RelayStorage
import RelaySearch
import RelaySecurity
import RelayNotifications
import RelayTasks
import RelayUI
import RelayCommandPacks

/// Locations and settings shared by every process that hosts Relay (the main app and the
/// menu bar companion). Both are unsandboxed, so they share one folder and one defaults suite.
public enum RelayShared {
    public static let defaultsSuiteName = "com.siveesh.skmole.relay"
    public static let customVariablesKey = "relay.customVariables"

    /// Posted (as a distributed notification) when hot key, variables, or library data changed
    /// in another process.
    public static let didChangeNotification = Notification.Name("com.siveesh.skmole.relay.didChange")

    /// Posted by the main app to ask the companion to open the command palette.
    public static let openPaletteNotification = Notification.Name("com.siveesh.skmole.relay.openPalette")

    public static func requestPalette() {
        DistributedNotificationCenter.default().postNotificationName(openPaletteNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    }

    /// `~/Library/Application Support/SK Mole/Relay`
    public static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("SK Mole", isDirectory: true)
            .appendingPathComponent("Relay", isDirectory: true)
    }

    public static func announceChange() {
        DistributedNotificationCenter.default().postNotificationName(didChangeNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Copies data from a standalone Relay install the first time Relay runs here. The original
    /// files are never modified or removed.
    public static func migrateStandaloneRelayDataIfNeeded() {
        let fileManager = FileManager.default
        let destination = dataDirectory
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        if let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let legacy = base.appendingPathComponent("Relay", isDirectory: true)
            for name in ["commands.json", "tasks.json", "history.json"] {
                let source = legacy.appendingPathComponent(name)
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.copyItem(at: source, to: destination.appendingPathComponent(name))
                }
            }
        }

        let defaults = Self.defaults
        let legacyDefaults = UserDefaults(suiteName: "com.relay.app")
        for key in [HotKeyPreference.userDefaultsKey, customVariablesKey] {
            if defaults.object(forKey: key) == nil, let value = legacyDefaults?.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }

    public static func loadCustomVariables() -> [String: String] {
        defaults.dictionary(forKey: customVariablesKey) as? [String: String] ?? [
            "NAS": "/Volumes/NAS",
            "CurrentProject": (NSHomeDirectory() as NSString).appendingPathComponent("Developer")
        ]
    }

    public static func saveCustomVariables(_ variables: [String: String]) {
        defaults.set(variables, forKey: customVariablesKey)
        announceChange()
    }
}

/// Composition root for Relay's services, shared by the main app and the companion.
@MainActor
public final class RelayEnvironment {
    public let search: any CommandSearching
    public let library: CommandLibraryModel
    public let taskLibrary: TaskLibraryModel
    public let history: HistoryModel
    public let runCoordinator: RunCoordinator
    public let notifications: any NotificationPosting
    public let commandStore: any CommandStoring

    private let executor: any CommandExecuting

    public init() {
        RelayShared.migrateStandaloneRelayDataIfNeeded()
        let directory = RelayShared.dataDirectory
        let executor = AuthorizedExecutor(base: ShellExecutor())
        let notifications = NotificationService()
        let resolver = VariableResolver(custom: RelayShared.loadCustomVariables(), context: SystemContextProvider())

        self.search = FuzzySearchEngine()
        self.executor = executor
        self.notifications = notifications
        let commandStore = JSONCommandStore(fileURL: directory.appendingPathComponent("commands.json"))
        self.commandStore = commandStore
        self.library = CommandLibraryModel(store: commandStore)
        self.taskLibrary = TaskLibraryModel(store: JSONTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
        self.history = HistoryModel(store: JSONHistoryStore(fileURL: directory.appendingPathComponent("history.json")))

        let taskRunner = TaskRunner(executor: executor, notifications: notifications, resolver: resolver)
        self.runCoordinator = RunCoordinator(
            executor: executor,
            notifications: notifications,
            resolver: resolver,
            taskRunner: taskRunner,
            history: history
        )
    }

    /// Reloads everything from disk, so changes made by the other process become visible.
    public func reload() async {
        await library.load()
        await taskLibrary.load()
        await history.load()
        runCoordinator.updateResolver(VariableResolver(custom: RelayShared.loadCustomVariables(), context: SystemContextProvider()))
    }

    public func makePaletteModel() -> CommandPaletteModel {
        CommandPaletteModel(commands: library.commands, search: search, usage: UsageStats.from(history.records))
    }
}
