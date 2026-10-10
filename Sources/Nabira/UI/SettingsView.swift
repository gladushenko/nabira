import AppKit
import Carbon
import Observation
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let showClipboardSettings = Notification.Name("Nabira.showClipboardSettings")
}

private enum SettingsModule: String, CaseIterable, Identifiable {
    case general = "General"
    case clipboard = "Clipboard"
    case shortcuts = "Shortcuts"
    case permissions = "Permissions"
    case about = "About"

    var id: Self { self }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .clipboard: "clipboard"
        case .shortcuts: "keyboard"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }

}

@MainActor @Observable private final class SettingsLocalState {
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var selection: SettingsModule? = .general
    var isClearHistoryConfirmationPresented = false
    var restoreDefaultsTarget: SettingsModule?
    var isRecordingShortcut = false
    var recordedShortcutDisplay: String?
    var shortcutValidationMessage: String?
    @ObservationIgnored private var shortcutMonitor: Any?
    @ObservationIgnored private var shortcutMouseMonitor: Any?
    @ObservationIgnored private var pendingShortcut: GlobalShortcut?
    @ObservationIgnored private var recordingDidChange: ((Bool) -> Void)?

    func startRecordingShortcut(
        recordingDidChange: @escaping (Bool) -> Void,
        onRecord: @escaping (GlobalShortcut) -> Void
    ) {
        stopRecordingShortcut()
        self.recordingDidChange = recordingDidChange
        shortcutValidationMessage = nil
        recordedShortcutDisplay = nil
        pendingShortcut = nil
        isRecordingShortcut = true
        recordingDidChange(true)
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags.rawValue
            let isKeyDown = event.type == .keyDown
            let isRepeat = event.isARepeat
            var shouldConsume = false
            MainActor.assumeIsolated {
                guard let self, self.isRecordingShortcut else { return }
                shouldConsume = true
                if isKeyDown, keyCode == 53 {
                    self.stopRecordingShortcut()
                    return
                }
                if isKeyDown {
                    guard !isRepeat else { return }
                    guard let shortcut = Self.shortcut(keyCode: keyCode, modifierFlags: modifierFlags) else {
                        self.shortcutValidationMessage = "Include Command, Option, Control, or Shift."
                        return
                    }
                    self.pendingShortcut = shortcut
                    self.recordedShortcutDisplay = shortcut.displayName
                    self.shortcutValidationMessage = nil
                    return
                }
                if let shortcut = self.pendingShortcut, shortcut.keyCode == UInt32(keyCode) {
                    onRecord(shortcut)
                    self.stopRecordingShortcut()
                }
            }
            return shouldConsume ? nil : event
        }
        shortcutMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.stopRecordingShortcut()
            }
            return event
        }
    }

    func stopRecordingShortcut() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        if let shortcutMouseMonitor {
            NSEvent.removeMonitor(shortcutMouseMonitor)
            self.shortcutMouseMonitor = nil
        }
        isRecordingShortcut = false
        pendingShortcut = nil
        recordedShortcutDisplay = nil
        recordingDidChange?(false)
        recordingDidChange = nil
    }

    private static func shortcut(keyCode: UInt16, modifierFlags: UInt) -> GlobalShortcut? {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers != 0 else { return nil }
        return GlobalShortcut(
            keyCode: UInt32(keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel(for: keyCode)
        )
    }

    private static func keyLabel(for keyCode: UInt16) -> String {
        let ansiLabels: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"
        ]
        if let label = ansiLabels[keyCode] { return label }
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key \(keyCode)"
        }
    }
}

struct SettingsView: View {
    @Environment(\.appLocalization) private var localized
    @Bindable var settings: AppSettings
    @Bindable var model: HistoryViewModel
    @State private var state = SettingsLocalState()

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsModule.allCases, selection: selectionBinding) { module in
                HStack(spacing: 16) {
                    Image(systemName: module.icon)
                        .font(.system(size: 15))
                        .frame(width: 20)
                    Text(localized.key(module.rawValue))
                }
                    .tag(module)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 38)
            .frame(width: 220)
            .background(SettingsSidebarBackground())

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(localized.key(selectedModule.rawValue))
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 38)
                    .padding(.bottom, 8)

                settingsDetail
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 520)
        .toolbar(.hidden, for: .windowToolbar)
        .onDisappear { state.stopRecordingShortcut() }
        .onReceive(NotificationCenter.default.publisher(for: .showClipboardSettings)) { _ in
            DispatchQueue.main.async {
                state.selection = .clipboard
            }
        }
        .alert(localized("Clear all clipboard history?"), isPresented: $state.isClearHistoryConfirmationPresented) {
            Button(localized("Cancel"), role: .cancel) {}
            Button(localized("Clear All"), role: .destructive) { model.clearAll() }
        } message: {
            Text(localized("All items, including Favorites, will be permanently deleted."))
        }
        .alert(localized("Restore Defaults?"), isPresented: restoreDefaultsConfirmationBinding) {
            Button(localized("Cancel"), role: .cancel) {}
            Button(localized("OK")) { restoreDefaults() }
        } message: {
            Text(localized.key(restoreDefaultsMessage))
        }
    }

    private var selectedModule: SettingsModule {
        state.selection ?? .general
    }

    private var selectionBinding: Binding<SettingsModule?> {
        Binding(
            get: { state.selection },
            set: { selection in
                DispatchQueue.main.async {
                    state.selection = selection
                }
            }
        )
    }

    private var restoreDefaultsConfirmationBinding: Binding<Bool> {
        Binding(
            get: { state.restoreDefaultsTarget != nil },
            set: { if !$0 { state.restoreDefaultsTarget = nil } }
        )
    }

    private var restoreDefaultsMessage: String {
        switch state.restoreDefaultsTarget {
        case .clipboard:
            "This will restore all Clipboard settings to their default values. Your clipboard history will not be deleted."
        case .shortcuts:
            "This will restore all keyboard shortcuts to their default values."
        default:
            "This will restore the default settings."
        }
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch selectedModule {
        case .general:
            Form {
                Toggle(localized("Launch at Login"), isOn: $state.launchAtLogin)
                    .controlSize(.large)
                    .onChange(of: state.launchAtLogin) { _, enabled in updateLaunchAtLogin(enabled) }
                Toggle(localized("Show in Dock"), isOn: $settings.showInDock)
                    .controlSize(.large)
                Picker(localized("Language"), selection: $settings.language) {
                    Text(localized("System")).tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Русский").tag(AppLanguage.russian)
                }
                Picker(localized("Appearance"), selection: $settings.appearance) { ForEach(AppAppearance.allCases) { Text(localized.key($0.rawValue)).tag($0) } }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

        case .clipboard:
            VStack(spacing: 0) {
                Form {
                    Section(localized("History")) {
                        Toggle(localized("Enable Clipboard"), isOn: $settings.isClipboardEnabled)
                            .controlSize(.large)
                        Toggle(localized("Paste on Single Click"), isOn: $settings.pasteOnSingleClick)
                            .controlSize(.large)
                        Toggle(localized("Show App Icons"), isOn: $settings.showClipboardPreviews)
                            .controlSize(.large)
                        LabeledContent(localized("Content Description")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(localized("Show All"), isOn: Binding(
                                    get: { settings.showAllClipboardDescriptions },
                                    set: { settings.setShowAllClipboardDescriptions($0) }
                                ))
                                .toggleStyle(.checkbox)

                                ForEach(ClipboardDescriptionOption.allCases) { option in
                                    Toggle(localized.key(option.rawValue), isOn: Binding(
                                        get: { settings.clipboardDescriptionOptions.contains(option) },
                                        set: { settings.setClipboardDescriptionOption(option, enabled: $0) }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .disabled(settings.showAllClipboardDescriptions)
                                }
                            }
                            .frame(minWidth: 150, alignment: .leading)
                        }
                        LabeledContent(localized("Maximum items"), value: "\(AppSettings.maxItems)")
                        LabeledContent(localized("Maximum favorites"), value: "\(AppSettings.maxPinnedItems)")
                        Picker(localized("Retention"), selection: $settings.retentionDays) {
                            Text(localized("1 day")).tag(1)
                            Text(localized("1 week")).tag(7)
                            Text(localized("2 weeks")).tag(14)
                            Text(localized("1 month")).tag(30)
                            Text(localized("2 months")).tag(60)
                        }
                        Button(localized("Clear Clipboard History…"), role: .destructive) {
                            state.isClearHistoryConfirmationPresented = true
                        }
                    }

                    Section(localized("Shortcuts")) {
                        clipboardHistoryShortcutSetting
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)

                restoreDefaultsButton(target: .clipboard)
            }

        case .shortcuts:
            VStack(spacing: 0) {
                Form {
                    Section(localized("Clipboard")) {
                        clipboardHistoryShortcutSetting
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)

                restoreDefaultsButton(target: .shortcuts)
            }

        case .about:
            AboutView()

        case .permissions:
            Form {
                Section(localized("Accessibility")) {
                    Button(localized("Open Permission Settings…")) { model.pasteCoordinator.requestAccessibility() }
                    Text(localized("Accessibility permission lets Nabira paste the selected clipboard item into the previously active application."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var clipboardHistoryShortcutSetting: some View {
        LabeledContent(localized("Open Clipboard")) {
            HStack(spacing: 12) {
                Button(
                    state.isRecordingShortcut
                        ? state.recordedShortcutDisplay ?? localized("Press keys…")
                        : settings.clipboardHistoryShortcut.displayName
                ) {
                    state.startRecordingShortcut(
                        recordingDidChange: { settings.setClipboardHistoryShortcutRecording($0) },
                        onRecord: { settings.clipboardHistoryShortcut = $0 }
                    )
                }
                .tint(state.isRecordingShortcut ? .accentColor : nil)
                Button {
                    state.stopRecordingShortcut()
                    settings.clipboardHistoryShortcut = .clipboardHistoryDefault
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(settings.clipboardHistoryShortcut == .clipboardHistoryDefault)
                .help(localized("Reset to default"))
            }
        }
        if let message = state.shortcutValidationMessage {
            Text(localized.key(message))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func restoreDefaultsButton(target: SettingsModule) -> some View {
        HStack {
            Spacer()
            Button(localized("Restore Defaults")) {
                state.restoreDefaultsTarget = target
            }
                .buttonStyle(.bordered)
                .tint(.secondary)
            Spacer()
        }
        .padding(.vertical, 16)
    }

    private func restoreDefaults() {
        let target = state.restoreDefaultsTarget
        state.restoreDefaultsTarget = nil
        state.stopRecordingShortcut()
        switch target {
        case .clipboard:
            settings.restoreClipboardDefaults()
        case .shortcuts:
            settings.restoreShortcutDefaults()
        default:
            break
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { state.launchAtLogin = SMAppService.mainApp.status == .enabled; model.errorMessage = error.localizedDescription }
    }
}

private struct SettingsSidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
