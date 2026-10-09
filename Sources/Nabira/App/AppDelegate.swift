import AppKit
import Observation

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var services: AppServices?
    private var windows: WindowCoordinator?
    private var menuBar: MenuBarController?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSettingsPresentation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
        startupTask = Task { [weak self] in
            do {
                let services = try await AppServices()
                try Task.checkCancellation()
                guard let self else { return }
                self.services = services
                let windows = WindowCoordinator(services: services)
                self.windows = windows
                let menuBar = MenuBarController(
                    settings: services.settings,
                    openLibrary: { [weak windows] in windows?.openLibrary() },
                    openSettings: { [weak windows] in windows?.openSettings() },
                    clearHistory: { [weak windows] in windows?.confirmClearHistory() }
                )
                self.menuBar = menuBar
                menuBar.configure()
                if services.settings.isClipboardEnabled { services.monitor.start() }
                services.settings.onClipboardEnabledChange = { [weak monitor = services.monitor] enabled in
                    if enabled { monitor?.start() } else { monitor?.stop() }
                }
                services.settings.onClipboardHistoryShortcutChange = { [weak self, weak menuBar] shortcut in
                    self?.registerClipboardHistoryShortcut(shortcut)
                    menuBar?.updateShortcut(shortcut)
                }
                services.settings.onClipboardHistoryShortcutRecordingChange = { [weak self, weak menuBar] isRecording in
                    guard let self, let services = self.services else { return }
                    if isRecording {
                        services.shortcuts.unregister(id: 1)
                        menuBar?.updateShortcut(nil)
                    } else {
                        self.registerClipboardHistoryShortcut(services.settings.clipboardHistoryShortcut)
                        menuBar?.updateShortcut(services.settings.clipboardHistoryShortcut)
                    }
                }
                registerClipboardHistoryShortcut(services.settings.clipboardHistoryShortcut)
                let completedOnboarding = UserDefaults.standard.bool(forKey: "completedOnboarding")
                if !completedOnboarding { windows.showOnboarding() }
                if pendingSettingsPresentation || (completedOnboarding && services.settings.showInDock) {
                    pendingSettingsPresentation = false
                    windows.openSettings()
                }
            } catch is CancellationError {
                return
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        windows?.applicationDidBecomeActive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard AppSettings.shared.showInDock else { return true }
        openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        windows?.stop()
        services?.monitor.stop()
        services?.shortcuts.unregisterAll()
    }

    func openSettings() {
        if let windows {
            windows.openSettings()
        } else {
            pendingSettingsPresentation = true
        }
    }

    private func registerClipboardHistoryShortcut(_ shortcut: GlobalShortcut) {
        services?.shortcuts.register(id: 1, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) {
            [weak windows] in
            windows?.openLibrary()
        }
    }
}
