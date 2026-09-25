import ServiceManagement
import SwiftUI

@MainActor private final class OnboardingState: ObservableObject {
    @Published var step = 0
    @Published var launchAtLogin = false
    @Published var directPaste = false
}

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    let pasteCoordinator: PasteCoordinator
    let finish: () -> Void
    @StateObject private var state = OnboardingState()

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: symbol).font(.system(size: 50)).foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            Text(message).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            stepControl
            Spacer()
            HStack {
                if state.step > 0 { Button("Back") { state.step -= 1 } }
                Spacer()
                Button(state.step == 5 ? "Start Using Nabira" : "Continue") {
                    if state.step == 5 { finish() } else { state.step += 1 }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 560, height: 420)
    }

    @ViewBuilder private var stepControl: some View {
        switch state.step {
        case 1:
            Toggle("Launch Nabira at login", isOn: $state.launchAtLogin)
                .onChange(of: state.launchAtLogin) { _, enabled in try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
        case 2:
            Text("⌘И").font(.system(size: 34, weight: .semibold, design: .rounded)).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        case 3:
            Toggle("Enable Direct Paste", isOn: $state.directPaste)
                .onChange(of: state.directPaste) { _, enabled in if enabled { pasteCoordinator.requestAccessibility() } }
        case 5:
            Text("Password managers are excluded automatically. Add other apps in Settings → Privacy.").font(.callout).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    private var title: String { ["Your clipboard, ready", "Start automatically", "One shortcut", "Direct Paste", "Private by design", "Review exclusions"][state.step] }
    private var message: String {
        ["Nabira keeps a searchable local history and lets you paste without leaving your keyboard.",
         "Keep Nabira available in the menu bar after every login.",
         "Press Command–И anywhere to open Clipboard History.",
         "Accessibility is requested only if you enable automatic pasting. Manual paste always works.",
         "Clipboard contents stay on this Mac. Nabira has no account, cloud API, or content analytics.",
         "Sensitive apps and concealed pasteboard content are never recorded."][state.step]
    }
    private var symbol: String { ["clipboard", "power", "keyboard", "hand.tap", "lock.shield", "checklist.checked"][state.step] }
}
