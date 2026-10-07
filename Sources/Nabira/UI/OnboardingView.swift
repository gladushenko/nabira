import ServiceManagement
import SwiftUI

struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let pasteCoordinator: PasteCoordinator
    let finish: () -> Void
    @State private var step = 0
    @State private var launchAtLogin = false
    @State private var directPaste = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: symbol).font(.system(size: 50)).foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            Text(message).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            stepControl
            Spacer()
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                Button(step == 4 ? "Start Using Nabira" : "Continue") {
                    if step == 4 { finish() } else { step += 1 }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 560, height: 420)
    }

    @ViewBuilder private var stepControl: some View {
        switch step {
        case 1:
            Toggle("Launch Nabira at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
        case 2:
            Text("⌘B").font(.system(size: 34, weight: .semibold, design: .rounded)).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        case 3:
            Toggle("Enable Direct Paste", isOn: $directPaste)
                .onChange(of: directPaste) { _, enabled in if enabled { pasteCoordinator.requestAccessibility() } }
        default: EmptyView()
        }
    }

    private var title: String { ["Your clipboard, ready", "Start automatically", "One shortcut", "Direct Paste", "Private by design"][step] }
    private var message: String {
        ["Nabira keeps a searchable local history and lets you paste without leaving your keyboard.",
         "Keep Nabira available in the menu bar after every login.",
         "Press Command–B anywhere to open Clipboard History.",
         "Accessibility is requested only if you enable automatic pasting. Manual paste always works.",
         "Clipboard contents stay on this Mac. Nabira has no account, cloud API, or content analytics."][step]
    }
    private var symbol: String { ["clipboard", "power", "keyboard", "hand.tap", "lock.shield"][step] }
}
