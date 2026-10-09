import AppKit
import SwiftUI

struct AboutView: View {
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
                        Text("Everyday tools for your Mac.")
                            .foregroundStyle(.secondary)
                        Text("Version \(info.version)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Project") {
                Link("Source Code", destination: repositoryURL)
            }

            Section("Local Data") {
                LabeledContent("Application data") {
                    Button("Open Folder") {
                        if let directory = try? AppInfo.dataDirectory() {
                            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(directory)
                        }
                    }
                }
                Text("Clipboard history is stored locally on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
