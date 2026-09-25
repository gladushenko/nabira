import AppKit
import SwiftUI

struct SourceIcon: View {
    let item: ClipboardItem

    var body: some View {
        Group {
            if let imagePreview {
                Image(nsImage: imagePreview)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1) }
                    .accessibilityLabel("Image preview")
            } else if let bundleID = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().aspectRatio(contentMode: .fit)
                    .accessibilityLabel(item.sourceAppName ?? "Unknown application")
            } else {
                Image(systemName: iconName).resizable().aspectRatio(contentMode: .fit).padding(3)
                    .accessibilityLabel(item.sourceAppName ?? "Unknown application")
            }
        }
        .frame(width: 36, height: 36)
    }

    private var imagePreview: NSImage? {
        guard item.contentType == .image else { return nil }
        return item.representations.lazy.compactMap { NSImage(data: $0.data) }.first
    }

    private var iconName: String {
        switch item.contentType {
        case .image: "photo"
        case .files: "doc"
        case .url: "link"
        case .color: "paintpalette"
        default: "doc.text"
        }
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    var body: some View {
        HStack(spacing: 12) {
            SourceIcon(item: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body).lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.contentType.label)
                    Text("•")
                    Text(relativeAge)
                    if item.copyCount > 1 { Text("• \(item.copyCount)×") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.isPinned { Image(systemName: "pin.fill").foregroundStyle(.secondary).accessibilityLabel("Pinned") }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var relativeAge: String {
        let totalMinutes = max(0, Int(Date().timeIntervalSince(item.lastCopiedAt))) / 60
        if totalMinutes < 1 { return "Less than a minute" }
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        return "\(totalMinutes / 60) h \(totalMinutes % 60) min"
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        ContentUnavailableView("Clipboard history is empty", systemImage: "clipboard", description: Text("Copy something in another app and it will appear here."))
    }
}
