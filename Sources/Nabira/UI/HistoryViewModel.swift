import AppKit
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var query = "" { didSet { scheduleReload() } }
    @Published var filter: HistoryFilter = .all { didSet { reload() } }
    @Published var selection: UUID?
    @Published var notice: String?
    @Published var errorMessage: String?

    let repository: ClipboardRepository
    let pasteCoordinator: PasteCoordinator
    private var searchTask: Task<Void, Never>?
    var limit = 100

    init(repository: ClipboardRepository, pasteCoordinator: PasteCoordinator) {
        self.repository = repository
        self.pasteCoordinator = pasteCoordinator
        pasteCoordinator.onNotice = { [weak self] in self?.notice = $0 }
    }

    var selectedItem: ClipboardItem? { items.first(where: { $0.id == selection }) }

    func reload() {
        do {
            items = query.isEmpty ? try repository.recent(limit: limit, filter: filter) : try repository.search(query, filter: filter, limit: limit)
            if selection == nil || !items.contains(where: { $0.id == selection }) { selection = items.first?.id }
        } catch { errorMessage = error.localizedDescription }
    }

    func scheduleReload() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func paste(_ item: ClipboardItem, plain: Bool = false) async -> PasteResult {
        await pasteCoordinator.paste(item, asPlainText: plain)
    }

    func paste(_ item: ClipboardItem, transformedBy transformation: TextTransformation) async -> PasteResult {
        guard let text = item.plainText else { return .failed("No text representation") }
        do {
            let transformed = try TextTransformer().transform(text, using: transformation)
            let representation = PasteboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(transformed.utf8))
            var result = item
            result.representations = [representation]
            result.searchableText = transformed
            return await pasteCoordinator.paste(result, asPlainText: true)
        } catch { errorMessage = error.localizedDescription; return .failed(error.localizedDescription) }
    }

    func togglePin(_ item: ClipboardItem) {
        do { try repository.setPinned(!item.isPinned, id: item.id); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ item: ClipboardItem) {
        do { try repository.delete(id: item.id); reload() }
        catch { errorMessage = error.localizedDescription }
    }
}
