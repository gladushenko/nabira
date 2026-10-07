import AppKit
import Carbon
import SwiftUI

private struct ClipboardMenuToggleView: View {
    @Bindable var settings: AppSettings

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
                        .fill(
                            settings.isClipboardEnabled
                                ? Color(nsColor: .controlAccentColor) : Color.secondary.opacity(0.3))
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

@MainActor
final class MenuBarController: NSObject {
    private let settings: AppSettings
    private let openLibraryAction: () -> Void
    private let openSettingsAction: () -> Void
    private let clearHistoryAction: () -> Void
    private var statusItem: NSStatusItem?
    private var clipboardHistoryMenuItem: NSMenuItem?

    init(
        settings: AppSettings, openLibrary: @escaping () -> Void,
        openSettings: @escaping () -> Void, clearHistory: @escaping () -> Void
    ) {
        self.settings = settings
        openLibraryAction = openLibrary
        openSettingsAction = openSettings
        clearHistoryAction = clearHistory
        super.init()
    }

    func configure() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "Nabira"
            statusItem?.button?.image = image
        }
        let menu = NSMenu()
        let clipboardHistoryItem = item("Show Clipboard", action: #selector(openLibrary))
        clipboardHistoryMenuItem = clipboardHistoryItem
        updateShortcut(settings.clipboardHistoryShortcut)
        menu.addItem(item("Nabira Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(clipboardHistoryItem)
        menu.addItem(item("Clear Clipboard History…", action: #selector(confirmClearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Nabira", action: #selector(quitNabira), key: "q"))
        menu.update()
        menu.insertItem(makeClipboardEnabledMenuItem(width: menu.size.width, settings: settings), at: 2)
        statusItem?.menu = menu
    }

    func updateShortcut(_ shortcut: GlobalShortcut?) {
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

    private func item(
        _ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }
    @objc private func openLibrary() { openLibraryAction() }
    @objc private func openSettings() { openSettingsAction() }
    @objc private func confirmClearHistory() { clearHistoryAction() }
    @objc private func quitNabira() { NSApp.terminate(nil) }
}
