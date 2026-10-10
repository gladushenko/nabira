import AppKit
import SwiftUI

struct LibraryView: View {
    @Environment(\.appLocalization) private var localized
    @Bindable var model: HistoryViewModel
    @Bindable var settings: AppSettings
    let openSettings: () -> Void
    let preview: (ClipboardItem) -> Void
    let close: (@escaping @MainActor () -> Void) -> Void
    private let controlHeight: CGFloat = 28
    private let controlCornerRadius: CGFloat = 10
    private let controlHorizontalPadding: CGFloat = 18
    private let controlVerticalSpacing: CGFloat = 18

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(localized("Search"), text: $model.query).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: controlHeight)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: controlCornerRadius))

                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: controlHeight, height: controlHeight)
                            .background(.quaternary, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(localized("Settings"))
                    .accessibilityLabel(localized("Settings"))
                }
                .padding(.horizontal, controlHorizontalPadding)
                .padding(.top, controlVerticalSpacing)
                .padding(.bottom, controlVerticalSpacing)

                HStack(spacing: 2) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Button {
                            model.filter = filter
                        } label: {
                            Label(localized.key(filter.rawValue), systemImage: icon(for: filter))
                                .font(.body)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .foregroundStyle(model.filter == filter ? Color.white : Color.primary)
                                .background {
                                    if model.filter == filter {
                                        RoundedRectangle(cornerRadius: controlCornerRadius - 2)
                                            .fill(Color.accentColor)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
                    }
                }
                .padding(2)
                .frame(height: controlHeight)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: controlCornerRadius))
                .padding(.horizontal, controlHorizontalPadding)
                .padding(.bottom, controlVerticalSpacing)

                if model.items.isEmpty {
                    EmptyHistoryView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                else {
                    List(model.items) { item in
                        ClipboardRow(
                            item: item,
                            isLastCopied: model.lastCopiedItemID == item.id,
                            showPreview: settings.showClipboardPreviews,
                            descriptionOptions: settings.clipboardDescriptionOptions,
                            pasteOnSingleClick: settings.pasteOnSingleClick,
                            paste: { pasteAndClose(item) },
                            preview: { preview(item) },
                            toggleFavorite: { model.toggleFavorite(item) },
                            loadPreview: { await model.previewImage(id: $0) }
                        )
                            .contextMenu {
                                Button(localized("Paste")) { pasteAndClose(item) }
                                if item.plainText != nil {
                                    Button(localized("Paste as Plain Text")) { pasteAndClose(item, plain: true) }
                                }
                                Button(localized("Preview")) { preview(item) }
                                if item.contentType.canBePinned {
                                    Button(localized.key(item.isPinned ? "Remove from Favorites" : "Add to Favorites")) {
                                        model.toggleFavorite(item)
                                    }
                                }
                                if item.plainText != nil {
                                    Menu(localized("Transform and Paste")) {
                                        ForEach(TextTransformation.allCases) { transformation in
                                            Button {
                                                transformPasteAndClose(item, using: transformation)
                                            } label: {
                                                Text(localized.key(transformation.rawValue))
                                                Text(localized.key(transformation.example))
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button(localized("Delete"), role: .destructive) { model.delete(item) }
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(localized("Nabira Clipboard"))
        }
        .onAppear { model.limit = AppSettings.maxItems + AppSettings.maxPinnedItems; model.reload() }
        .alert(localized("Favorites limit reached"), isPresented: Binding(
            get: { model.favoritesLimitMessage != nil },
            set: { if !$0 { model.favoritesLimitMessage = nil } }
        )) {
            Button(localized("OK")) { model.favoritesLimitMessage = nil }
        } message: {
            Text(localized("You can add up to \(AppSettings.maxPinnedItems) items to Favorites."))
        }
    }

    private func pasteAndClose(_ item: ClipboardItem, plain: Bool = false) {
        close {
            Task {
                _ = await model.paste(item, plain: plain)
            }
        }
    }

    private func transformPasteAndClose(_ item: ClipboardItem, using transformation: TextTransformation) {
        close {
            Task {
                _ = await model.paste(item, transformedBy: transformation)
            }
        }
    }

    private func icon(for filter: HistoryFilter) -> String {
        switch filter { case .all: "clock"; case .favorites: "star"; case .text: "doc.text"; case .links: "link"; case .images: "photo"; case .files: "folder" }
    }
}
