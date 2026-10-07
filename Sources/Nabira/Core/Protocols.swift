import AppKit
import Foundation

protocol ClipboardRepository: Sendable {
    func upsert(_ item: ClipboardItem) async throws -> ClipboardItem
    func recent(limit: Int, filter: HistoryFilter) async throws -> [ClipboardItem]
    func search(_ query: String, filter: HistoryFilter, limit: Int) async throws -> [ClipboardItem]
    func previewImage(id: UUID) async throws -> Data?
    func item(id: UUID) async throws -> ClipboardItem?
    func setPinned(_ pinned: Bool, id: UUID) async throws
    func delete(id: UUID) async throws
    func clear(since: Date?, includePinned: Bool) async throws
    func prune(maxItems: Int, maxBytes: Int, olderThan: Date) async throws
}

protocol PrivacyFiltering: Sendable {
    func decision(for candidate: ClipboardCandidate, settings: SettingsSnapshot) -> PrivacyDecision
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
