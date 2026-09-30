import AppKit
import ServiceManagement
import SwiftUI

private enum SettingsModule: String, CaseIterable, Identifiable {
    case general = "General"
    case clipboard = "Clipboard"
    case permissions = "Permissions"

    var id: Self { self }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .clipboard: "clipboard"
        case .permissions: "lock.shield"
        }
    }
}

@MainActor private final class SettingsLocalState: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var excludedID = ""
    @Published var selection: SettingsModule? = .general
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: HistoryViewModel
    @StateObject private var state = SettingsLocalState()

    var body: some View {
        NavigationSplitView {
            List(SettingsModule.allCases, selection: selectionBinding) { module in
                Label(module.rawValue, systemImage: module.icon)
                    .tag(module)
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            settingsDetail
                .navigationTitle(selectedModule.rawValue)
                .toggleStyle(.switch)
        }
        .frame(minWidth: 760, minHeight: 520)
        .toolbar(.hidden, for: .windowToolbar)
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

    @ViewBuilder
    private var settingsDetail: some View {
        switch selectedModule {
        case .general:
            Form {
                Toggle("Launch at Login", isOn: $state.launchAtLogin)
                    .controlSize(.large)
                    .onChange(of: state.launchAtLogin) { _, enabled in updateLaunchAtLogin(enabled) }
                Toggle("Show in Dock", isOn: $settings.showInDock)
                    .controlSize(.large)
                Picker("Appearance", selection: $settings.appearance) { ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) } }
            }
            .formStyle(.grouped)

        case .clipboard:
            Form {
                Section("History") {
                    LabeledContent("Maximum items", value: "\(AppSettings.maxItems)")
                    LabeledContent("Maximum pinned items", value: "\(AppSettings.maxPinnedItems)")
                    Picker("Retention", selection: $settings.retentionDays) {
                        Text("1 week").tag(7)
                        Text("2 weeks").tag(14)
                        Text("1 month").tag(30)
                    }
                    Toggle("Show pinned items first", isOn: $settings.showPinnedFirst)
                        .controlSize(.large)
                }

                Section("Privacy") {
                    Picker("One-time codes", selection: $settings.otpBehavior) { ForEach(OTPBehavior.allCases) { Text($0.rawValue).tag($0) } }
                    ForEach(Array(settings.excludedBundleIDs).sorted(), id: \.self) { id in HStack { Text(id); Spacer(); Button("Remove") { settings.excludedBundleIDs.remove(id) } } }
                    HStack { TextField("Bundle identifier", text: $state.excludedID); Button("Add") { if !state.excludedID.isEmpty { settings.excludedBundleIDs.insert(state.excludedID); state.excludedID = "" } } }
                }

                Section("Shortcuts") {
                    LabeledContent("Clipboard History", value: "⌘B")
                    LabeledContent("Paste plain text", value: "⌘↩")
                    LabeledContent("Pin / unpin", value: "⌘S")
                    LabeledContent("Delete", value: "⌘⌫")
                    LabeledContent("Quick Look", value: "Space")
                    Text("Shortcut recording and conflict detection are isolated behind ShortcutHandling for a future editor.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

        case .permissions:
            Form {
                Section("Accessibility") {
                    Button("Enable Direct Paste…") { model.pasteCoordinator.requestAccessibility() }
                    Text("Accessibility permission lets Nabira paste the selected clipboard item into the previously active application.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { state.launchAtLogin = SMAppService.mainApp.status == .enabled; model.errorMessage = error.localizedDescription }
    }
}
