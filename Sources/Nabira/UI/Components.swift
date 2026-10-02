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
    let paste: () -> Void
    let preview: () -> Void
    let toggleFavorite: () -> Void
    @StateObject private var state = ClipboardRowState()
    private let contentHeight: CGFloat = 70
    private let metadataRowHeight: CGFloat = 10
    private let actionButtonSize: CGFloat = 10

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showPreview {
                SourceIcon(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture(count: pasteOnSingleClick ? 1 : 2, perform: paste)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        if showMetadata {
                            Text(item.contentType.label)
                            Text("•")
                            Text(relativeAge)
                        }
                        Spacer(minLength: 4)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: pasteOnSingleClick ? 1 : 2, perform: paste)

                    actionButtons
                }
                .frame(height: metadataRowHeight, alignment: .top)

                Text(displayedContent)
                    .font(.title2)
                    .lineLimit(2)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: contentHeight - metadataRowHeight - 6,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: pasteOnSingleClick ? 1 : 2, perform: paste)
            }
            .frame(maxWidth: .infinity, minHeight: contentHeight, alignment: .top)
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

    private var actionButtons: some View {
        HStack(spacing: 16) {
            actionButton(title: "Preview", systemImage: "eye", action: preview)
                .opacity(state.isHovering ? 1 : 0)
                .allowsHitTesting(state.isHovering)
                .accessibilityHidden(!state.isHovering)

            if item.contentType.canBePinned {
                actionButton(
                    title: item.isPinned ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: item.isPinned ? "star.fill" : "star",
                    action: toggleFavorite
                )
                .opacity(item.isPinned || state.isHovering ? 1 : 0)
                .allowsHitTesting(item.isPinned || state.isHovering)
                .accessibilityHidden(!item.isPinned && !state.isHovering)
            }
        }
        .animation(.easeInOut(duration: 0.05), value: state.isHovering)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 12))
                .frame(width: actionButtonSize, height: actionButtonSize)
        }
        .buttonStyle(.borderless)
        .help(title)
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
