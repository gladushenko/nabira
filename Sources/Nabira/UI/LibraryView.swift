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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Category", selection: $model.filter) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Label(filter.rawValue, systemImage: icon(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $model.query).textFieldStyle(.plain)
                }
                .padding(10)

                Divider()

                if model.items.isEmpty {
                    EmptyHistoryView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                else {
                    List(model.items) { item in
                        ClipboardRow(item: item)
                            .onTapGesture { pasteAndClose(item) }
                            .contextMenu {
                                Button("Paste") { pasteAndClose(item) }
                                Button("Paste as Plain Text") { pasteAndClose(item, plain: true) }
                                if item.plainText != nil {
                                    Menu("Transform and Paste") {
                                        ForEach(TextTransformation.allCases.filter { $0 != .plain }) { transformation in
                                            Button(transformation.rawValue) { transformPasteAndClose(item, using: transformation) }
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
