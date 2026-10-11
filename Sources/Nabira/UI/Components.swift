import AppKit
import SwiftUI

struct SourceIcon: View {
    @Environment(\.appLocalization) private var localized
    let item: ClipboardItem
    let loadPreview: (UUID) async -> Data?
    @State private var imagePreview: NSImage?
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
                    .accessibilityLabel(localized("Image preview"))
            } else if let bundleID = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .accessibilityLabel(item.sourceAppName ?? localized("Unknown application"))
            } else {
                Image(systemName: iconName)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .accessibilityLabel(item.sourceAppName ?? localized("Unknown application"))
            }
        }
        .frame(width: containerSize, height: containerSize)
        .fixedSize()
        .clipped()
        .task(id: item.id) {
            imagePreview = nil
            guard item.contentType == .image,
                  let data = await loadPreview(item.id), !Task.isCancelled else { return }
            imagePreview = NSImage(data: data)
        }
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
    @Environment(\.appLocalization) private var localized
    let item: ClipboardItem
    var isLastCopied = false
    let showPreview: Bool
    let descriptionOptions: Set<ClipboardDescriptionOption>
    let pasteOnSingleClick: Bool
    let paste: () -> Void
    let preview: () -> Void
    let toggleFavorite: () -> Void
    let loadPreview: (UUID) async -> Data?
    @State private var isHovering = false
    private let metadataRowHeight: CGFloat = 10
    private let actionButtonSize: CGFloat = 10

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showPreview {
                SourceIcon(item: item, loadPreview: loadPreview)
                    .contentShape(Rectangle())
                    .onTapGesture(count: pasteOnSingleClick ? 1 : 2, perform: paste)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    actionButtons

                    HStack(spacing: 2) {
                        Spacer(minLength: 4)
                        metadataContent
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture(count: pasteOnSingleClick ? 1 : 2, perform: paste)
                }
                .frame(height: metadataRowHeight, alignment: .top)

                ZStack(alignment: .leading) {
                    // Reserve two lines without aligning short content to the top.
                    Text("\n")
                        .lineLimit(2, reservesSpace: true)
                        .hidden()
                        .accessibilityHidden(true)

                    Text(displayedContent)
                        .lineLimit(3)
                }
                .font(.title2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: pasteOnSingleClick ? 1 : 2, perform: paste)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.trailing, 14)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isLastCopied ? Color.accentColor.opacity(0.20) : isHovering ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .accessibilityValue(isLastCopied ? localized("Last copied item") : "")
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            if item.contentType.canBePinned {
                actionButton(
                    title: item.isPinned ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: item.isPinned ? "star.fill" : "star",
                    action: toggleFavorite
                )
                .opacity(item.isPinned || isHovering ? 1 : 0)
                .allowsHitTesting(item.isPinned || isHovering)
                .accessibilityHidden(!item.isPinned && !isHovering)
            }

            actionButton(title: "Preview", systemImage: "eye", action: preview)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .accessibilityHidden(!isHovering)
        }
        .animation(.easeInOut(duration: 0.05), value: isHovering)
    }

    private var metadataContent: some View {
        Text(metadataDescriptions.joined(separator: " • "))
    }

    private var metadataDescriptions: [String] {
        var descriptions: [String] = []
        if descriptionOptions.contains(.contentType) {
            descriptions.append(localized.key(item.contentType.label))
        }
        if descriptionOptions.contains(.characterCount), let count = item.characterCount {
            descriptions.append(localized("\(count) chars"))
        }
        if descriptionOptions.contains(.time) {
            descriptions.append(relativeAge)
        }
        return descriptions
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(localized.key(title), systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 12))
                .frame(width: actionButtonSize, height: actionButtonSize)
        }
        .buttonStyle(.borderless)
        .help(localized.key(title))
    }

    private var displayedContent: String {
        if item.contentType == .image, item.title == "Image" { return localized("Image") }
        if [.text, .richText, .html, .url, .color].contains(item.contentType),
           !item.searchableText.isEmpty {
            return item.searchableText
        }
        guard item.contentType == .files else { return item.title }
        if item.title.hasPrefix("file://"),
           let url = URL(string: item.searchableText), url.isFileURL { return url.path }
        return item.title
    }

    private var relativeAge: String {
        let totalMinutes = max(0, Int(Date().timeIntervalSince(item.lastCopiedAt))) / 60
        if totalMinutes < 1 { return localized("Less than a minute ago") }
        if totalMinutes < 60 { return localized("\(totalMinutes) min ago") }
        return localized("\(totalMinutes / 60) h \(totalMinutes % 60) min ago")
    }
}

struct EmptyHistoryView: View {
    @Environment(\.appLocalization) private var localized
    var body: some View {
        ContentUnavailableView(localized("Clipboard history is empty"), systemImage: "clipboard", description: Text(localized("Copy something in another app and it will appear here.")))
    }
}
