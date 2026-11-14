import SwiftUI

@main
struct SKMoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Warren", id: "main-window") {
            RootView(model: model)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) { }
            MoleCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
        }

        Window("About Warren", id: "about-window") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Warren Help", id: "help-window") {
            HelpView()
        }
        .defaultSize(width: 720, height: 680)
    }
}
