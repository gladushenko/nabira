import AppKit
import SwiftUI

private final class ClipboardHistoryWindow: NSPanel {
    var dismiss: (() -> Void)?
    var openSettings: (() -> Void)?
    var willDismiss: (() -> Void)?
    private var restingFrame: NSRect?

    func presentAnimated() {
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

    func dismissImmediately(completion: (@MainActor () -> Void)? = nil) {
        guard isVisible else {
            completion?()
            return
        }
        willDismiss?()
        orderOut(nil)
        if let restingFrame { setFrame(restingFrame, display: false) }
        alphaValue = 1
        completion?()
    }

    private func scaledFrame(from frame: NSRect) -> NSRect {
        frame.insetBy(dx: frame.width * 0.015, dy: frame.height * 0.015)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, event.keyCode == 43,
            modifiers.subtracting([.capsLock, .numericPad, .function]) == [.command]
        {
            openSettings?()
            return true
        }
        return super.performKeyEquivalent(with: event)
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

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let services: AppServices
    private var libraryWindow: ClipboardHistoryWindow?
    private var previewWindow: NSWindow?
    private var previewTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var isClosingPreview = false
    private var outsideClickMonitor: Any?
    private weak var windowAwaitingActivation: NSWindow?

    init(services: AppServices) {
        self.services = services
        super.init()
    }

    func applicationDidBecomeActive() {
        windowAwaitingActivation?.makeKeyAndOrderFront(nil)
        windowAwaitingActivation = nil
    }

    func stop() {
        previewTask?.cancel()
        stopOutsideClickMonitor()
    }

    func openLibrary() {
        if libraryWindow?.isVisible == true {
            libraryWindow?.dismissImmediately()
            return
        }
        services.pasteCoordinator.captureTarget()
        services.libraryModel.filter = .all
        services.libraryModel.query = ""
        if libraryWindow == nil {
            let window = ClipboardHistoryWindow(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 720, height: 500)),
                styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.title = "Clipboard History"
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.animationBehavior = .none
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            configureFixedWindowAppearance(window)
            window.dismiss = { [weak window] in window?.dismissImmediately() }
            window.openSettings = { [weak self] in self?.openSettings() }
            window.willDismiss = { [weak self] in
                self?.stopOutsideClickMonitor()
                self?.hidePreviewForLibraryDismissal()
            }
            window.contentView = NSHostingView(
                rootView: LibraryView(
                    model: services.libraryModel,
                    settings: services.settings,
                    openSettings: { [weak self, weak window] in
                        window?.dismissImmediately()
                        self?.openClipboardSettings()
                    },
                    preview: { [weak self] item in self?.openPreview(item) },
                    close: { [weak window] completion in
                        guard let window else {
                            completion()
                            return
                        }
                        window.dismissImmediately(completion: completion)
                    }
                ))
            libraryWindow = window
            libraryWindow?.delegate = self
            libraryWindow?.contentMinSize = NSSize(width: 600, height: 360)
        }
        positionLibraryWindow()
        libraryWindow?.presentAnimated()
        startOutsideClickMonitor()
        DispatchQueue.main.async { [weak libraryWindow] in libraryWindow?.makeFirstResponder(nil) }
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.libraryWindow?.dismissImmediately()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func openPreview(_ item: ClipboardItem) {
        previewTask?.cancel()
        let services = services
        previewTask = Task { [weak self] in
            do {
                let fullItem = try await services.libraryModel.loadItem(item)
                guard !Task.isCancelled, let self, self.libraryWindow?.isVisible == true else { return }
                self.presentPreview(fullItem)
            } catch { services.libraryModel.errorMessage = error.localizedDescription }
        }
    }

    private func presentPreview(_ item: ClipboardItem) {
        let rootView = ClipboardPreviewView(item: item)
        if previewWindow == nil {
            let window = makeWindow(
                title: "Preview",
                size: NSSize(width: 780, height: 520),
                rootView: rootView
            )
            window.contentMinSize = NSSize(width: 520, height: 320)
            window.delegate = self
            previewWindow = window
        } else {
            previewWindow?.contentView = NSHostingView(rootView: rootView)
        }
        center(previewWindow)
        if let libraryWindow, let previewWindow,
            libraryWindow.childWindows?.contains(previewWindow) != true
        {
            libraryWindow.addChildWindow(previewWindow, ordered: .above)
        }
        show(previewWindow)
    }

    private func center(_ window: NSWindow?) {
        guard let window,
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let visibleFrame = screen.visibleFrame
        window.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            ))
    }

    private func hidePreviewForLibraryDismissal() {
        previewTask?.cancel()
        guard let previewWindow else { return }
        libraryWindow?.removeChildWindow(previewWindow)
        previewWindow.orderOut(nil)
    }

    private func positionLibraryWindow() {
        guard let window = libraryWindow, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let width = min(max(visibleFrame.width * 0.30, 600), 720)
        let size = NSSize(width: width, height: visibleFrame.height * 0.65)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            window === libraryWindow || window === previewWindow
        else { return }
        if window === previewWindow, isClosingPreview { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let keyWindow = NSApp.keyWindow
            guard keyWindow !== self.libraryWindow, keyWindow !== self.previewWindow else { return }
            guard self.services.libraryModel.favoritesLimitMessage == nil else { return }
            self.libraryWindow?.dismissImmediately()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === previewWindow {
            isClosingPreview = true
        } else if sender === libraryWindow {
            stopOutsideClickMonitor()
            hidePreviewForLibraryDismissal()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === previewWindow else { return }
        libraryWindow?.removeChildWindow(window)
        if libraryWindow?.isVisible == true {
            libraryWindow?.makeKey()
        }
        DispatchQueue.main.async { [weak self] in
            self?.isClosingPreview = false
        }
    }
    @objc func openSettings() {
        scheduleSettingsPresentation(showClipboardSection: false)
    }

    private func scheduleSettingsPresentation(showClipboardSection: Bool) {
        // Menu tracking must finish before a window takes keyboard focus.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.presentSettings(showClipboardSection: showClipboardSection)
            }
        }
    }

    private func presentSettings(showClipboardSection: Bool) {
        libraryWindow?.dismissImmediately()
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "Nabira Settings", size: NSSize(width: 760, height: 520),
                rootView: SettingsView(settings: services.settings, model: services.libraryModel))
            if let settingsWindow {
                configureFixedWindowAppearance(settingsWindow)
                settingsWindow.styleMask.insert(.fullSizeContentView)
                settingsWindow.titleVisibility = .hidden
            }
        }
        center(settingsWindow)
        show(settingsWindow)
        if showClipboardSection {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showClipboardSettings, object: nil)
            }
        }
    }

    private func openClipboardSettings() {
        scheduleSettingsPresentation(showClipboardSection: true)
    }

    func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "All items, including Favorites, will be permanently deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        services.libraryModel.clearAll()
    }

    private func configureFixedWindowAppearance(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.styleMask.remove(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: rootView)
        return window
    }

    private func show(_ window: NSWindow?) {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        windowAwaitingActivation = NSApp.isActive ? nil : window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        let view = OnboardingView(settings: services.settings, pasteCoordinator: services.pasteCoordinator) {
            [weak self] in
            UserDefaults.standard.set(true, forKey: "completedOnboarding")
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        onboardingWindow = makeWindow(title: "Welcome to Nabira", size: NSSize(width: 560, height: 420), rootView: view)
        onboardingWindow?.isMovableByWindowBackground = true
        show(onboardingWindow)
    }
}
