import AppKit
import Carbon
import SwiftUI

private final class ClipboardHistoryWindow: NSWindow {
    var dismiss: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            dismiss?()
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss?()
    }
}

@main
struct NabiraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            if let services = delegate.services { SettingsView(settings: services.settings, model: services.libraryModel) }
        }
    }
}

@MainActor
final class AppServices {
    let settings = AppSettings.shared
    let repository: SQLiteClipboardRepository
    let monitor: ClipboardMonitor
    let pasteCoordinator: PasteCoordinator
    let libraryModel: HistoryViewModel
    let shortcuts = GlobalShortcutManager()

    init() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "Nabira")
        repository = try SQLiteClipboardRepository(path: support.appending(path: "history.sqlite3").path)
        monitor = ClipboardMonitor(repository: repository, privacy: PrivacyGuard(), settings: settings)
        pasteCoordinator = PasteCoordinator(monitor: monitor, settings: settings)
        libraryModel = HistoryViewModel(repository: repository, pasteCoordinator: pasteCoordinator)
        monitor.onCapture = { [weak libraryModel] _ in libraryModel?.reload() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var services: AppServices?
    private var statusItem: NSStatusItem?
    private var libraryWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
        do {
            let services = try AppServices()
            self.services = services
            services.monitor.start()
            // Key code 11 is the physical B key, which produces “И” in the Russian layout.
            services.shortcuts.register(id: 1, keyCode: 11, modifiers: UInt32(cmdKey)) { [weak self] in self?.openLibrary() }
            configureMenuBar()
            if !UserDefaults.standard.bool(forKey: "completedOnboarding") { showOnboarding() }
        } catch {
            let alert = NSAlert(error: error); alert.runModal(); NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { services?.monitor.stop(); services?.shortcuts.unregisterAll() }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Nabira")
        let menu = NSMenu()
        menu.addItem(item("Open Clipboard History", action: #selector(openLibrary), key: "b"))
        menu.addItem(item("Clear All History…", action: #selector(confirmClearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(item("Quit Nabira", action: #selector(quitNabira), key: "q"))
        statusItem?.menu = menu
    }

    private func item(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; item.keyEquivalentModifierMask = modifiers; return item
    }
    @objc private func openLibrary() {
        guard let services else { return }
        if libraryWindow?.isVisible == true {
            libraryWindow?.orderOut(nil)
            return
        }
        services.pasteCoordinator.captureTarget()
        services.libraryModel.filter = .all
        services.libraryModel.query = ""
        if libraryWindow == nil {
            let window = ClipboardHistoryWindow(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 760, height: 500)),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Clipboard History"
            window.isReleasedWhenClosed = false
            window.dismiss = { [weak window] in window?.orderOut(nil) }
            window.contentView = NSHostingView(rootView: LibraryView(model: services.libraryModel) { [weak window] in window?.orderOut(nil) })
            libraryWindow = window
            libraryWindow?.delegate = self
            libraryWindow?.contentMinSize = NSSize(width: 600, height: 360)
        }
        positionLibraryWindow()
        show(libraryWindow)
        DispatchQueue.main.async { [weak libraryWindow] in libraryWindow?.makeFirstResponder(nil) }
    }

    private func positionLibraryWindow() {
        guard let window = libraryWindow, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let size = NSSize(width: min(760, visibleFrame.width), height: visibleFrame.height / 2)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === libraryWindow else { return }
        window.orderOut(nil)
    }
    @objc private func openSettings() {
        guard let services else { return }
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Nabira Settings", size: NSSize(width: 620, height: 430), rootView: SettingsView(settings: services.settings, model: services.libraryModel))
        }
        show(settingsWindow)
    }
    @objc private func quitNabira() { NSApp.terminate(nil) }
    @objc private func confirmClearHistory() {
        guard let services else { return }
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "All items, including pinned items, will be permanently deleted. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try services.repository.clear(since: nil, includePinned: true)
            services.libraryModel.reload()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.center()
        window.contentView = NSHostingView(rootView: rootView)
        return window
    }

    private func show(_ window: NSWindow?) {
        NSApp.activate(); window?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        guard let services else { return }
        let view = OnboardingView(settings: services.settings, pasteCoordinator: services.pasteCoordinator) { [weak self] in
            UserDefaults.standard.set(true, forKey: "completedOnboarding")
            self?.onboardingWindow?.close(); self?.onboardingWindow = nil
        }
        onboardingWindow = makeWindow(title: "Welcome to Nabira", size: NSSize(width: 560, height: 420), rootView: view)
        onboardingWindow?.isMovableByWindowBackground = true
        show(onboardingWindow)
    }
}
