import AppKit
import ServiceManagement
import SwiftUI

@MainActor private final class SettingsLocalState: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var excludedID = ""
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: HistoryViewModel
    @StateObject private var state = SettingsLocalState()

    var body: some View {
        TabView {
            Form {
                Toggle("Launch at Login", isOn: $state.launchAtLogin).onChange(of: state.launchAtLogin) { _, enabled in updateLaunchAtLogin(enabled) }
                Toggle("Show in Dock", isOn: $settings.showInDock)
                Picker("Appearance", selection: $settings.appearance) { ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) } }
                LabeledContent("Global shortcut", value: "⌘И")
            }.padding().tabItem { Label("General", systemImage: "gear") }

            Form {
                Stepper("Maximum items: \(settings.maxItems)", value: $settings.maxItems, in: 100...50_000, step: 100)
                Stepper("Retention: \(settings.retentionDays) days", value: $settings.retentionDays, in: 1...365)
                Stepper("Maximum item size: \(settings.maxItemMB) MB", value: $settings.maxItemMB, in: 1...500)
                Toggle("Save images", isOn: $settings.captureImages)
                Toggle("Show pinned items first", isOn: $settings.showPinnedFirst)
            }.padding().tabItem { Label("History", systemImage: "clock") }

            Form {
                Toggle("Restore clipboard after paste", isOn: $settings.restoreClipboard)
                Button("Enable Direct Paste…") { model.pasteCoordinator.requestAccessibility() }
                Text("Without Accessibility permission, Nabira copies the selected item so you can paste it manually.").font(.caption).foregroundStyle(.secondary)
            }.padding().tabItem { Label("Paste", systemImage: "arrow.right.doc.on.clipboard") }

            Form {
                Picker("One-time codes", selection: $settings.otpBehavior) { ForEach(OTPBehavior.allCases) { Text($0.rawValue).tag($0) } }
                Section("Excluded applications") {
                    ForEach(Array(settings.excludedBundleIDs).sorted(), id: \.self) { id in HStack { Text(id); Spacer(); Button("Remove") { settings.excludedBundleIDs.remove(id) } } }
                    HStack { TextField("Bundle identifier", text: $state.excludedID); Button("Add") { if !state.excludedID.isEmpty { settings.excludedBundleIDs.insert(state.excludedID); state.excludedID = "" } } }
                }
            }.padding().tabItem { Label("Privacy", systemImage: "hand.raised") }

            Form {
                LabeledContent("Open Clipboard History", value: "⌘И")
                LabeledContent("Paste plain text", value: "⌘↩")
                LabeledContent("Pin / unpin", value: "⌘S")
                LabeledContent("Delete", value: "⌘⌫")
                LabeledContent("Quick Look", value: "Space")
                Text("Shortcut recording and conflict detection are isolated behind ShortcutHandling for a future editor.").font(.caption).foregroundStyle(.secondary)
            }.padding().tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 620, height: 430)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { state.launchAtLogin = SMAppService.mainApp.status == .enabled; model.errorMessage = error.localizedDescription }
    }
}
