import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    var items: [ClipboardItem] = []
    var query = "" { didSet { scheduleReload() } }
    var filter: HistoryFilter = .all { didSet { reload() } }
    var selection: UUID?
    var lastCopiedItemID: UUID?
    var notice: String?
    var errorMessage: String?
    var favoritesLimitMessage: String?

    let repository: ClipboardRepository
    let pasteCoordinator: PasteCoordinator
    private let transformer = TextTransformer()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    var limit = 100

    init(repository: ClipboardRepository, pasteCoordinator: PasteCoordinator) {
        self.repository = repository
        self.pasteCoordinator = pasteCoordinator
        pasteCoordinator.onNotice = { [weak self] in self?.notice = $0 }
        pasteCoordinator.onCopied = { [weak self] in self?.lastCopiedItemID = $0 }
    }

    var selectedItem: ClipboardItem? { items.first(where: { $0.id == selection }) }

    @discardableResult
    func reload() -> Task<Void, Never> {
        scheduleReload(debounce: false)
    }

    @discardableResult
    func scheduleReload(debounce: Bool = true) -> Task<Void, Never> {
        searchTask?.cancel()
        let query = query
        let filter = filter
        let limit = limit
        let repository = repository
        let task = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(150)) }
                try Task.checkCancellation()
                let items =
                    query.isEmpty
                    ? try await repository.recent(limit: limit, filter: filter)
                    : try await repository.search(query, filter: filter, limit: limit)
                try Task.checkCancellation()
                guard let self else { return }
                self.items = items
                if self.selection == nil || !items.contains(where: { $0.id == self.selection }) {
                    self.selection = items.first?.id
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
            }
        }
        searchTask = task
        return task
    }

    func paste(_ item: ClipboardItem, plain: Bool = false) async -> PasteResult {
        do {
            let fullItem = try await loadItem(item)
            return await pasteCoordinator.paste(fullItem, asPlainText: plain)
        } catch { return .failed(error.localizedDescription) }
    }

    func paste(_ item: ClipboardItem, transformedBy transformation: TextTransformation) async -> PasteResult {
        do {
            let item = try await loadItem(item)
            guard let text = item.plainText else { return .failed("No text representation") }
            let transformed = try await transformer.transform(text, using: transformation)
            let representation = PasteboardRepresentation(
                type: NSPasteboard.PasteboardType.string.rawValue, data: Data(transformed.utf8))
            var result = item
            result.representations = [representation]
            result.searchableText = transformed
            return await pasteCoordinator.paste(result, asPlainText: true)
        } catch {
            errorMessage = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    func loadItem(_ item: ClipboardItem) async throws -> ClipboardItem {
        if item.hasLoadedRepresentations { return item }
        guard let fullItem = try await repository.item(id: item.id) else {
            throw NabiraError.noPasteableContent
        }
        return fullItem
    }

    func previewImage(id: UUID) async -> Data? {
        try? await repository.previewImage(id: id)
    }

    func toggleFavorite(_ item: ClipboardItem) {
        guard item.contentType.canBePinned else { return }
        Task {
            do {
                try await repository.setPinned(!item.isPinned, id: item.id)
                reload()
            } catch NabiraError.pinLimitReached {
                favoritesLimitMessage = "You can add up to \(AppSettings.maxPinnedItems) items to Favorites."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ item: ClipboardItem) {
        Task {
            do {
                try await repository.delete(id: item.id)
                reload()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func clearAll() {
        Task {
            do {
                try await repository.clear(since: nil, includePinned: true)
                reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
