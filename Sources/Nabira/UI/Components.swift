import AppKit
import SwiftUI

@MainActor private final class ClipboardRowState: ObservableObject {
    @Published var isHovering = false
}

struct SourceIcon: View {
    let item: ClipboardItem
    private let containerSize: CGFloat = 70
    private let cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            if let imagePreview {
                Image(nsImage: imagePreview)
                    .resizable()
                    .scaledToFit()
                    .frame(width: containerSize, height: containerSize)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay { RoundedRectangle(cornerRadius: cornerRadius).stroke(.separator, lineWidth: 1) }
                    .accessibilityLabel("Image preview")
            } else if let bundleID = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .accessibilityLabel(item.sourceAppName ?? "Unknown application")
            } else {
                Image(systemName: iconName)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .accessibilityLabel(item.sourceAppName ?? "Unknown application")
            }
        }
        .frame(width: containerSize, height: containerSize)
        .fixedSize()
        .clipped()
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
    let showPreview: Bool
    let showMetadata: Bool
    let pasteOnSingleClick: Bool
    let select: () -> Void
    let preview: () -> Void
    let toggleFavorite: () -> Void
    @StateObject private var state = ClipboardRowState()

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                if showPreview {
                    SourceIcon(item: item)
                }
                VStack(alignment: .leading, spacing: 5) {
                    if showMetadata {
                        HStack(spacing: 6) {
                            Text(item.contentType.label)
                            Text("•")
                            Text(relativeAge)
                        }
                        .font(.callout).foregroundStyle(.secondary)
                    }
                    Text(displayedContent)
                        .font(.title2)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: pasteOnSingleClick ? 1 : 2, perform: select)

            HStack(spacing: 8) {
                Button(action: preview) {
                    Label("Preview", systemImage: "eye")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Preview")

                if item.contentType.canBePinned {
                    Button(action: toggleFavorite) {
                        Label(
                            item.isPinned ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: item.isPinned ? "star.fill" : "star"
                        )
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help(item.isPinned ? "Remove from Favorites" : "Add to Favorites")
                }
            }
            .padding(.trailing, 14)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(state.isHovering ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .onHover { state.isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: state.isHovering)
    }

    private var displayedContent: String {
        guard item.contentType == .files else { return item.title }
        if item.title.hasPrefix("file://"),
           let url = URL(string: item.searchableText), url.isFileURL { return url.path }
        return item.title
    }

    private var relativeAge: String {
        let totalMinutes = max(0, Int(Date().timeIntervalSince(item.lastCopiedAt))) / 60
        if totalMinutes < 1 { return "Less than a minute ago" }
        if totalMinutes < 60 { return "\(totalMinutes) min ago" }
        return "\(totalMinutes / 60) h \(totalMinutes % 60) min ago"
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        ContentUnavailableView("Clipboard history is empty", systemImage: "clipboard", description: Text("Copy something in another app and it will appear here."))
    }
}
