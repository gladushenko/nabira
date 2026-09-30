import AppKit
import Foundation

@MainActor
protocol ClipboardCapturing: AnyObject {
    func start()
    func stop()
}

protocol ClipboardRepository: Sendable {
    func upsert(_ item: ClipboardItem) throws -> ClipboardItem
    func recent(limit: Int, filter: HistoryFilter) throws -> [ClipboardItem]
    func search(_ query: String, filter: HistoryFilter, limit: Int) throws -> [ClipboardItem]
    func item(id: UUID) throws -> ClipboardItem?
    func setPinned(_ pinned: Bool, id: UUID) throws
    func delete(id: UUID) throws
    func clear(since: Date?, includePinned: Bool) throws
    func prune(maxItems: Int, maxBytes: Int, olderThan: Date) throws
}

protocol SearchProviding: Sendable {
    func search(_ query: String, filter: HistoryFilter, limit: Int) throws -> [ClipboardItem]
}

protocol TextInserting: AnyObject {
    @MainActor func paste(_ item: ClipboardItem, asPlainText: Bool) async -> PasteResult
}

protocol ContentTransforming: Sendable {
    func transform(_ text: String, using transformation: TextTransformation) throws -> String
}

protocol PrivacyFiltering: Sendable {
    func decision(for candidate: ClipboardCandidate, settings: SettingsSnapshot) -> PrivacyDecision
}

@MainActor
protocol ShortcutHandling: AnyObject {
    func registerDefaultShortcuts()
    func unregisterAll()
}

struct ClipboardCandidate: Sendable {
    let representations: [PasteboardRepresentation]
    let sourceBundleID: String?
    let searchableText: String
    let contentType: ClipboardContentType
    let byteCount: Int
}

enum PrivacyDecision: Equatable, Sendable {
    case allow
    case ignore(String)
    case expire(after: TimeInterval)
}

enum PasteResult: Sendable {
    case inserted
    case copiedPermissionNeeded
    case failed(String)
}
