import SwiftUI

@main
struct NabiraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            if let services = delegate.services { SettingsView(settings: services.settings, model: services.libraryModel) }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Nabira Settings…") { delegate.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
