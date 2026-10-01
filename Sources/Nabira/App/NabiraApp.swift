import AppKit
import Carbon
import SwiftUI

private struct ClipboardMenuToggleView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button {
            settings.isClipboardEnabled.toggle()
        } label: {
            HStack(spacing: 8) {
                Text("Enable Clipboard")
                    .foregroundStyle(.primary)
                Spacer()
                ZStack(alignment: settings.isClipboardEnabled ? .trailing : .leading) {
                    Capsule()
                        .fill(settings.isClipboardEnabled ? Color(nsColor: .controlAccentColor) : Color.secondary.opacity(0.3))
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                }
                .frame(width: 32, height: 18)
                .animation(.easeOut(duration: 0.12), value: settings.isClipboardEnabled)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 15)
        .frame(height: 28)
    }
}

private final class ClipboardHistoryWindow: NSPanel {
    var dismiss: (() -> Void)?
    private var isDismissing = false
    private var restingFrame: NSRect?

    func presentAnimated() {
        isDismissing = false
        let finalFrame = frame
        restingFrame = finalFrame
        alphaValue = 0
        setFrame(scaledFrame(from: finalFrame), display: false)
        orderFrontRegardless()
        makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(finalFrame, display: true)
        }
    }

    func dismissAnimated() {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        let finalFrame = restingFrame ?? frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.07
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(horizontallyScaledFrame(from: finalFrame, scale: 1.025), display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    animator().alphaValue = 0
                    animator().setFrame(horizontallyScaledFrame(from: finalFrame, scale: 0.92), display: true)
                } completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        orderOut(nil)
                        setFrame(finalFrame, display: false)
                        alphaValue = 1
                        isDismissing = false
                    }
                }
            }
        }
    }

    private func horizontallyScaledFrame(from frame: NSRect, scale: CGFloat) -> NSRect {
        let width = frame.width * scale
        return NSRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
    }

    private func scaledFrame(from frame: NSRect) -> NSRect {
        frame.insetBy(dx: frame.width * 0.015, dy: frame.height * 0.015)
    }

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
        pasteCoordinator = PasteCoordinator(monitor: monitor)
        libraryModel = HistoryViewModel(repository: repository, pasteCoordinator: pasteCoordinator)
        monitor.onCapture = { [weak libraryModel] _ in libraryModel?.reload() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var services: AppServices?
    private var statusItem: NSStatusItem?
    private var clipboardHistoryMenuItem: NSMenuItem?
    private var libraryWindow: ClipboardHistoryWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
        do {
            let services = try AppServices()
            self.services = services
            if services.settings.isClipboardEnabled {
                services.monitor.start()
            }
            services.settings.onClipboardEnabledChange = { [weak self] isEnabled in
                guard let self, let services = self.services else { return }
                if isEnabled {
                    services.monitor.start()
                } else {
                    services.monitor.stop()
                }
            }
            services.settings.onClipboardHistoryShortcutChange = { [weak self] shortcut in
                self?.registerClipboardHistoryShortcut(shortcut)
                self?.updateClipboardHistoryMenuShortcut(shortcut)
            }
            services.settings.onClipboardHistoryShortcutRecordingChange = { [weak self] isRecording in
                guard let self, let services = self.services else { return }
                if isRecording {
                    services.shortcuts.unregister(id: 1)
                    self.updateClipboardHistoryMenuShortcut(nil)
                } else {
                    self.registerClipboardHistoryShortcut(services.settings.clipboardHistoryShortcut)
                    self.updateClipboardHistoryMenuShortcut(services.settings.clipboardHistoryShortcut)
                }
            }
            registerClipboardHistoryShortcut(services.settings.clipboardHistoryShortcut)
            configureMenuBar()
            if !UserDefaults.standard.bool(forKey: "completedOnboarding") { showOnboarding() }
        } catch {
            let alert = NSAlert(error: error); alert.runModal(); NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { services?.monitor.stop(); services?.shortcuts.unregisterAll() }

    private func registerClipboardHistoryShortcut(_ shortcut: GlobalShortcut) {
        services?.shortcuts.register(id: 1, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.openLibrary()
        }
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Nabira")
        let menu = NSMenu()
        let clipboardHistoryItem = item("Show Clipboard", action: #selector(openLibrary))
        clipboardHistoryMenuItem = clipboardHistoryItem
        updateClipboardHistoryMenuShortcut(services?.settings.clipboardHistoryShortcut)
        menu.addItem(item("Nabira Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(clipboardHistoryItem)
        menu.addItem(item("Clear Clipboard History…", action: #selector(confirmClearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Nabira", action: #selector(quitNabira), key: "q"))
        menu.update()
        if let settings = services?.settings {
            menu.insertItem(makeClipboardEnabledMenuItem(width: menu.size.width, settings: settings), at: 2)
        }
        statusItem?.menu = menu
    }

    private func updateClipboardHistoryMenuShortcut(_ shortcut: GlobalShortcut?) {
        guard let item = clipboardHistoryMenuItem else { return }
        guard let shortcut else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = menuKeyEquivalent(for: shortcut)
        var modifiers: NSEvent.ModifierFlags = []
        if shortcut.modifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if shortcut.modifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        item.keyEquivalentModifierMask = modifiers
    }

    private func makeClipboardEnabledMenuItem(width: CGFloat, settings: AppSettings) -> NSMenuItem {
        let menuItem = NSMenuItem()
        let view = NSHostingView(rootView: ClipboardMenuToggleView(settings: settings))
        view.frame = NSRect(x: 0, y: 0, width: width, height: 28)
        menuItem.view = view
        return menuItem
    }

    private func menuKeyEquivalent(for shortcut: GlobalShortcut) -> String {
        switch shortcut.keyCode {
        case 36: return "\r"
        case 48: return "\t"
        case 49: return " "
        case 51: return "\u{8}"
        case 117: return "\u{7f}"
        case 123: return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case 124: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case 125: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case 126: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        default: return shortcut.keyLabel.lowercased()
        }
    }

    private func item(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; item.keyEquivalentModifierMask = modifiers; return item
    }
    @objc private func openLibrary() {
        guard let services else { return }
        if libraryWindow?.isVisible == true {
            libraryWindow?.dismissAnimated()
            return
        }
        services.pasteCoordinator.captureTarget()
        services.libraryModel.filter = .all
        services.libraryModel.query = ""
        if libraryWindow == nil {
            let window = ClipboardHistoryWindow(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 720, height: 500)),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.title = "Clipboard History"
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.animationBehavior = .none
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.dismiss = { [weak window] in window?.dismissAnimated() }
            window.contentView = NSHostingView(rootView: LibraryView(
                model: services.libraryModel,
                settings: services.settings,
                openSettings: { [weak self, weak window] in
                    window?.dismissAnimated()
                    self?.openClipboardSettings()
                },
                close: { [weak window] in window?.dismissAnimated() }
            ))
            libraryWindow = window
            libraryWindow?.delegate = self
            libraryWindow?.contentMinSize = NSSize(width: 600, height: 360)
        }
        positionLibraryWindow()
        libraryWindow?.presentAnimated()
        DispatchQueue.main.async { [weak libraryWindow] in libraryWindow?.makeFirstResponder(nil) }
    }

    private func positionLibraryWindow() {
        guard let window = libraryWindow, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let width = min(max(visibleFrame.width * 0.30, 600), 720)
        let size = NSSize(width: width, height: visibleFrame.height * 0.55)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === libraryWindow else { return }
        guard services?.libraryModel.pinLimitMessage == nil else { return }
        libraryWindow?.dismissAnimated()
    }
    @objc private func openSettings() {
        guard let services else { return }
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Nabira Settings", size: NSSize(width: 760, height: 520), rootView: SettingsView(settings: services.settings, model: services.libraryModel))
        }
        positionSettingsWindow()
        show(settingsWindow)
    }

    private func openClipboardSettings() {
        openSettings()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showClipboardSettings, object: nil)
        }
    }

    private func positionSettingsWindow() {
        guard let window = settingsWindow,
              let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        ))
    }
    @objc private func quitNabira() { NSApp.terminate(nil) }
    @objc private func confirmClearHistory() {
        guard let services else { return }
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "All items, including pinned items, will be permanently deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        services.libraryModel.clearAll()
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
