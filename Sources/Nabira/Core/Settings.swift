import AppKit
import Carbon
import Foundation

struct GlobalShortcut: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let clipboardHistoryDefault = GlobalShortcut(keyCode: 11, modifiers: UInt32(cmdKey), keyLabel: "B")

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }
}

struct SettingsSnapshot: Sendable {
    var maxItems: Int
    var retentionDays: Int
    var maxItemBytes: Int
    var maxImageBytes: Int
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let maxItems = 300
    nonisolated static let maxPinnedItems = 10
    static let defaultRetentionDays = 30
    static let defaultClipboardEnabled = true
    static let defaultShowClipboardPreviews = true
    static let defaultShowClipboardMetadata = true
    static let maxHistoryBytes = 2 * 1_024 * 1_024 * 1_024
    static let maxItemBytes = 20 * 1_024 * 1_024
    static let maxImageBytes = 100 * 1_024 * 1_024
    static let retentionOptions = [1, 7, 14, 30, 60]

    private let defaults = UserDefaults.standard
    var onClipboardHistoryShortcutChange: ((GlobalShortcut) -> Void)?
    var onClipboardHistoryShortcutRecordingChange: ((Bool) -> Void)?
    var onClipboardEnabledChange: ((Bool) -> Void)?

    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays") } }
    @Published var isClipboardEnabled: Bool {
        didSet {
            defaults.set(isClipboardEnabled, forKey: "isClipboardEnabled")
            onClipboardEnabledChange?(isClipboardEnabled)
        }
    }
    @Published var showClipboardPreviews: Bool { didSet { defaults.set(showClipboardPreviews, forKey: "showClipboardPreviews") } }
    @Published var showClipboardMetadata: Bool { didSet { defaults.set(showClipboardMetadata, forKey: "showClipboardMetadata") } }
    @Published var clipboardHistoryShortcut: GlobalShortcut {
        didSet {
            defaults.set(Int(clipboardHistoryShortcut.keyCode), forKey: "clipboardShortcutKeyCode")
            defaults.set(Int(clipboardHistoryShortcut.modifiers), forKey: "clipboardShortcutModifiers")
            defaults.set(clipboardHistoryShortcut.keyLabel, forKey: "clipboardShortcutKeyLabel")
            onClipboardHistoryShortcutChange?(clipboardHistoryShortcut)
        }
    }
    @Published var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock"); applyDockPolicy() } }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }

    private init() {
        defaults.register(defaults: [
            "retentionDays": Self.defaultRetentionDays,
            "isClipboardEnabled": Self.defaultClipboardEnabled,
            "showClipboardPreviews": Self.defaultShowClipboardPreviews,
            "showClipboardMetadata": Self.defaultShowClipboardMetadata,
            "clipboardShortcutKeyCode": Int(GlobalShortcut.clipboardHistoryDefault.keyCode),
            "clipboardShortcutModifiers": Int(GlobalShortcut.clipboardHistoryDefault.modifiers),
            "clipboardShortcutKeyLabel": GlobalShortcut.clipboardHistoryDefault.keyLabel,
            "showInDock": false
        ])
        let storedRetentionDays = defaults.integer(forKey: "retentionDays")
        retentionDays = Self.retentionOptions.contains(storedRetentionDays) ? storedRetentionDays : Self.defaultRetentionDays
        isClipboardEnabled = defaults.bool(forKey: "isClipboardEnabled")
        showClipboardPreviews = defaults.bool(forKey: "showClipboardPreviews")
        showClipboardMetadata = defaults.bool(forKey: "showClipboardMetadata")
        clipboardHistoryShortcut = GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: "clipboardShortcutKeyCode")),
            modifiers: UInt32(defaults.integer(forKey: "clipboardShortcutModifiers")),
            keyLabel: defaults.string(forKey: "clipboardShortcutKeyLabel") ?? GlobalShortcut.clipboardHistoryDefault.keyLabel
        )
        showInDock = defaults.bool(forKey: "showInDock")
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    }

    var snapshot: SettingsSnapshot {
        SettingsSnapshot(maxItems: Self.maxItems, retentionDays: retentionDays,
                         maxItemBytes: Self.maxItemBytes, maxImageBytes: Self.maxImageBytes)
    }

    func setClipboardHistoryShortcutRecording(_ isRecording: Bool) {
        onClipboardHistoryShortcutRecordingChange?(isRecording)
    }

    func restoreClipboardDefaults() {
        isClipboardEnabled = Self.defaultClipboardEnabled
        showClipboardPreviews = Self.defaultShowClipboardPreviews
        showClipboardMetadata = Self.defaultShowClipboardMetadata
        retentionDays = Self.defaultRetentionDays
        clipboardHistoryShortcut = .clipboardHistoryDefault
    }

    func restoreShortcutDefaults() {
        clipboardHistoryShortcut = .clipboardHistoryDefault
    }

    private func applyDockPolicy() {
        NSApp?.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    private func applyAppearance() {
        NSApp?.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
