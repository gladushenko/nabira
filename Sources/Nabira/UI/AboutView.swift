import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.appLocalization) private var localized
    private let info = AppInfo()
    private let repositoryURL = URL(string: "https://github.com/gladushenko/nabira")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nabira")
                            .font(.title.bold())
                        Text(localized("Everyday tools for your Mac."))
                            .foregroundStyle(.secondary)
                        Text(localized("Version \(info.version)"))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(localized("Project")) {
                Link(localized("Source Code"), destination: repositoryURL)
            }

            Section(localized("Local Data")) {
                LabeledContent(localized("Application data")) {
                    Button(localized("Open Folder")) {
                        if let directory = try? AppInfo.dataDirectory() {
                            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(directory)
                        }
                    }
                }
                Text(localized("Clipboard history is stored locally on this Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
