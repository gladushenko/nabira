import AppKit
import Carbon
import Foundation
import Observation

enum ClipboardDescriptionOption: String, CaseIterable, Identifiable, Sendable {
    case contentType = "Content Type"
    case characterCount = "Character Count"
    case time = "Time"

    var id: Self { self }
}

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
@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let maxItems = 300
    nonisolated static let maxPinnedItems = 10
    static let defaultRetentionDays = 30
    static let defaultClipboardEnabled = true
    static let defaultShowClipboardPreviews = true
    static let defaultClipboardDescriptionOptions = Set(ClipboardDescriptionOption.allCases)
    static let defaultShowAllClipboardDescriptions = true
    static let defaultPasteOnSingleClick = true
    static let maxHistoryBytes = 2 * 1_024 * 1_024 * 1_024
    static let maxItemBytes = 20 * 1_024 * 1_024
    static let maxImageBytes = 100 * 1_024 * 1_024
    static let retentionOptions = [1, 7, 14, 30, 60]

    private let defaults: UserDefaults
    @ObservationIgnored var onClipboardHistoryShortcutChange: ((GlobalShortcut) -> Void)?
    @ObservationIgnored var onClipboardHistoryShortcutRecordingChange: ((Bool) -> Void)?
    @ObservationIgnored var onClipboardEnabledChange: ((Bool) -> Void)?
    @ObservationIgnored var onLanguageChange: (() -> Void)?

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            onLanguageChange?()
        }
    }

    @ObservationIgnored var onRetentionDaysChange: (() -> Void)?
    var retentionDays: Int {
        didSet {
            defaults.set(retentionDays, forKey: "retentionDays")
            onRetentionDaysChange?()
        }
    }
    var isClipboardEnabled: Bool {
        didSet {
            defaults.set(isClipboardEnabled, forKey: "isClipboardEnabled")
            onClipboardEnabledChange?(isClipboardEnabled)
        }
    }
    var showClipboardPreviews: Bool { didSet { defaults.set(showClipboardPreviews, forKey: "showClipboardPreviews") } }
    var clipboardDescriptionOptions: Set<ClipboardDescriptionOption> {
        didSet {
            defaults.set(clipboardDescriptionOptions.map(\.rawValue).sorted(), forKey: "clipboardDescriptionOptions")
        }
    }
    var showAllClipboardDescriptions: Bool {
        didSet { defaults.set(showAllClipboardDescriptions, forKey: "showAllClipboardDescriptions") }
    }
    var pasteOnSingleClick: Bool { didSet { defaults.set(pasteOnSingleClick, forKey: "pasteOnSingleClick") } }
    var clipboardHistoryShortcut: GlobalShortcut {
        didSet {
            defaults.set(Int(clipboardHistoryShortcut.keyCode), forKey: "clipboardShortcutKeyCode")
            defaults.set(Int(clipboardHistoryShortcut.modifiers), forKey: "clipboardShortcutModifiers")
            defaults.set(clipboardHistoryShortcut.keyLabel, forKey: "clipboardShortcutKeyLabel")
            onClipboardHistoryShortcutChange?(clipboardHistoryShortcut)
        }
    }
    var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock"); applyDockPolicy() } }
    var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        let storedDescriptionOptions = defaults.stringArray(forKey: "clipboardDescriptionOptions")
        let storedShowAllDescriptions = defaults.object(forKey: "showAllClipboardDescriptions") as? Bool
        let legacyDescriptionMode = defaults.string(forKey: "clipboardDescriptionMode")
        defaults.register(defaults: [
            "retentionDays": Self.defaultRetentionDays,
            "isClipboardEnabled": Self.defaultClipboardEnabled,
            "showClipboardPreviews": Self.defaultShowClipboardPreviews,
            "clipboardDescriptionOptions": Self.defaultClipboardDescriptionOptions.map(\.rawValue),
            "showAllClipboardDescriptions": Self.defaultShowAllClipboardDescriptions,
            "pasteOnSingleClick": Self.defaultPasteOnSingleClick,
            "clipboardShortcutKeyCode": Int(GlobalShortcut.clipboardHistoryDefault.keyCode),
            "clipboardShortcutModifiers": Int(GlobalShortcut.clipboardHistoryDefault.modifiers),
            "clipboardShortcutKeyLabel": GlobalShortcut.clipboardHistoryDefault.keyLabel,
            "showInDock": false
        ])
        let storedRetentionDays = defaults.integer(forKey: "retentionDays")
        retentionDays = Self.retentionOptions.contains(storedRetentionDays) ? storedRetentionDays : Self.defaultRetentionDays
        isClipboardEnabled = defaults.bool(forKey: "isClipboardEnabled")
        showClipboardPreviews = defaults.bool(forKey: "showClipboardPreviews")
        let migratedDescriptionOptions: Set<ClipboardDescriptionOption> = switch legacyDescriptionMode {
        case "Content Type Only": [.contentType]
        case "Character Count Only": [.characterCount]
        case "Time Only": [.time]
        default: Self.defaultClipboardDescriptionOptions
        }
        let savedDescriptionOptions = Set(
            (storedDescriptionOptions ?? []).compactMap(ClipboardDescriptionOption.init(rawValue:))
        )
        let showAllDescriptions = storedShowAllDescriptions
            ?? (legacyDescriptionMode == nil || legacyDescriptionMode == "Show All")
        showAllClipboardDescriptions = showAllDescriptions
        clipboardDescriptionOptions = showAllDescriptions
            ? Self.defaultClipboardDescriptionOptions
            : (storedDescriptionOptions == nil ? migratedDescriptionOptions : savedDescriptionOptions)
        pasteOnSingleClick = defaults.bool(forKey: "pasteOnSingleClick")
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
        clipboardDescriptionOptions = Self.defaultClipboardDescriptionOptions
        showAllClipboardDescriptions = Self.defaultShowAllClipboardDescriptions
        pasteOnSingleClick = Self.defaultPasteOnSingleClick
        retentionDays = Self.defaultRetentionDays
        clipboardHistoryShortcut = .clipboardHistoryDefault
    }

    func setShowAllClipboardDescriptions(_ enabled: Bool) {
        showAllClipboardDescriptions = enabled
        if enabled {
            clipboardDescriptionOptions = Self.defaultClipboardDescriptionOptions
        }
    }

    func setClipboardDescriptionOption(_ option: ClipboardDescriptionOption, enabled: Bool) {
        if enabled {
            clipboardDescriptionOptions.insert(option)
        } else {
            clipboardDescriptionOptions.remove(option)
        }
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
