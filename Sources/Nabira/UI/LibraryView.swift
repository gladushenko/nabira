import AppKit
import SwiftUI

@MainActor private final class LibraryLocalState: ObservableObject {
    @Published var renaming: ClipboardItem?
    @Published var newTitle = ""
}

struct LibraryView: View {
    @ObservedObject var model: HistoryViewModel
    let close: () -> Void
    @StateObject private var state = LibraryLocalState()
    private let controlHeight: CGFloat = 28
    private let controlCornerRadius: CGFloat = 10
    private let controlHorizontalPadding: CGFloat = 18
    private let controlVerticalSpacing: CGFloat = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Button {
                            model.filter = filter
                        } label: {
                            Label(filter.rawValue, systemImage: icon(for: filter))
                                .font(.body)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .padding(.top, controlVerticalSpacing + 3)
                .padding(.bottom, controlVerticalSpacing + 3)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $model.query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: controlHeight)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: controlCornerRadius))
                .padding(.horizontal, controlHorizontalPadding)
                .padding(.bottom, controlVerticalSpacing + 3)

                if model.items.isEmpty {
                    EmptyHistoryView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                else {
                    List(model.items) { item in
                        ClipboardRow(
                            item: item,
                            select: { pasteAndClose(item) },
                            togglePin: { model.togglePin(item) }
                        )
                            .contextMenu {
                                Button("Paste") { pasteAndClose(item) }
                                if item.plainText != nil {
                                    Menu("Transform and Paste") {
                                        ForEach(TextTransformation.allCases) { transformation in
                                            Button {
                                                transformPasteAndClose(item, using: transformation)
                                            } label: {
                                                Text(transformation.rawValue)
                                                Text(transformation.example)
                                            }
                                        }
                                    }
                                }
                                Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
                                if item.isPinned { Button("Rename…") { state.newTitle = item.title; state.renaming = item } }
                                Divider()
                                Button("Delete", role: .destructive) { model.delete(item) }
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Clipboard History")
        }
        .onAppear { model.limit = 5_000; model.reload() }
        .alert("Rename Pinned Item", isPresented: Binding(get: { state.renaming != nil }, set: { if !$0 { state.renaming = nil } })) {
            TextField("Name", text: $state.newTitle)
            Button("Cancel", role: .cancel) { state.renaming = nil }
            Button("Save") { if let item = state.renaming { try? model.repository.rename(id: item.id, title: state.newTitle); model.reload() }; state.renaming = nil }
        }
    }

    private func pasteAndClose(_ item: ClipboardItem, plain: Bool = false) {
        close()
        Task {
            _ = await model.paste(item, plain: plain)
        }
    }

    private func transformPasteAndClose(_ item: ClipboardItem, using transformation: TextTransformation) {
        close()
        Task {
            _ = await model.paste(item, transformedBy: transformation)
        }
    }

    private func icon(for filter: HistoryFilter) -> String {
        switch filter { case .all: "clock"; case .pinned: "pin"; case .text: "doc.text"; case .links: "link"; case .images: "photo"; case .files: "folder" }
    }
}
