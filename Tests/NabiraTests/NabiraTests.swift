import AppKit
import Foundation
import Testing
@testable import Nabira

private func makeItem(_ text: String, date: Date = .now) -> ClipboardItem {
    let representation = PasteboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))
    return ClipboardItem(id: UUID(), contentType: .text, searchableText: text, title: text,
                         representations: [representation], sourceBundleID: "com.example.source", sourceAppName: "Example",
                         firstCopiedAt: date, lastCopiedAt: date, copyCount: 1, byteCount: representation.data.count,
                         isPinned: false, contentHash: ContentHasher.hash([representation]), pinnedOrder: nil)
}

private func repository() throws -> SQLiteClipboardRepository {
    try SQLiteClipboardRepository(path: FileManager.default.temporaryDirectory.appending(path: "nabira-\(UUID().uuidString).sqlite3").path)
}

@Suite struct NabiraTests {
    @Test func deduplicatesAndUpdatesRecency() throws {
        let repo = try repository()
        let first = makeItem("same", date: Date(timeIntervalSince1970: 1))
        _ = try repo.upsert(first)
        var second = makeItem("same", date: Date(timeIntervalSince1970: 2))
        second.contentHash = first.contentHash
        let stored = try repo.upsert(second)
        #expect(try repo.recent(limit: 10, filter: .all).count == 1)
        #expect(stored.copyCount == 2)
        #expect(stored.lastCopiedAt == second.lastCopiedAt)
    }

    @Test func pinnedItemsSurvivePruning() throws {
        let repo = try repository()
        let old = makeItem("old", date: Date(timeIntervalSince1970: 1))
        _ = try repo.upsert(old)
        try repo.setPinned(true, id: old.id)
        try repo.prune(maxItems: 1, olderThan: .now)
        #expect(try repo.item(id: old.id) != nil)
    }

    @Test func clearAllRemovesPinnedAndUnpinnedItems() throws {
        let repo = try repository()
        let pinned = makeItem("pinned")
        let unpinned = makeItem("unpinned")
        _ = try repo.upsert(pinned)
        _ = try repo.upsert(unpinned)
        try repo.setPinned(true, id: pinned.id)

        try repo.clear(since: nil, includePinned: true)

        #expect(try repo.recent(limit: 10, filter: .all).isEmpty)
    }

    @Test func fullTextSearch() throws {
        let repo = try repository()
        _ = try repo.upsert(makeItem("a surprisingly specific nebula phrase"))
        #expect(try repo.search("nebula", filter: .all, limit: 10).count == 1)
        #expect(try repo.search("missing", filter: .all, limit: 10).isEmpty)
    }

    @Test func privacyFiltersAndOTP() {
        let guardService = PrivacyGuard()
        let settings = SettingsSnapshot(maxItems: 5_000, retentionDays: 30, maxItemBytes: 10_000, captureImages: true,
                                        excludedBundleIDs: ["blocked.app"], ignoredPasteboardTypes: ["org.nspasteboard.ConcealedType"], otpBehavior: .ignore)
        let rep = PasteboardRepresentation(type: "public.utf8-plain-text", data: Data("hello".utf8))
        #expect(guardService.decision(for: .init(representations: [rep], sourceBundleID: "blocked.app", searchableText: "hello", contentType: .text, byteCount: 5), settings: settings) == .ignore("Excluded application"))
        let secret = PasteboardRepresentation(type: "org.nspasteboard.ConcealedType", data: Data())
        #expect(guardService.decision(for: .init(representations: [secret], sourceBundleID: nil, searchableText: "secret", contentType: .text, byteCount: 0), settings: settings) == .ignore("Private pasteboard type"))
        #expect(PrivacyGuard.looksLikeOTP("123456"))
        #expect(!PrivacyGuard.looksLikeOTP("invoice 123456"))
    }

    @Test func textTransformations() throws {
        let transformer = TextTransformer()
        #expect(try transformer.transform("  a   b  ", using: .trim) == "a   b")
        #expect(try transformer.transform("a   b", using: .collapseSpaces) == "a b")
        #expect(try transformer.transform("a\n \nb", using: .removeEmptyLines) == "a\nb")
        #expect(try transformer.transform("{\"b\":2,\"a\":1}", using: .jsonMinify) == "{\"a\":1,\"b\":2}")
    }

    @MainActor @Test func fileURLIsDisplayedAsAPath() {
        let pasteboardItem = NSPasteboardItem()
        let fileURL = "file:///Users/example/My%20File.txt"
        pasteboardItem.setString(fileURL, forType: .fileURL)
        let representation = PasteboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data(fileURL.utf8))

        let classified = ClipboardMonitor.classify(item: pasteboardItem, representations: [representation])

        #expect(classified.type == .files)
        #expect(classified.text == "/Users/example/My File.txt")
    }

    @MainActor @Test func selfCaptureChangeCountCanBeIgnored() throws {
        let board = NSPasteboard(name: .init("NabiraTests-\(UUID())"))
        let repo = try repository()
        let monitor = ClipboardMonitor(pasteboard: board, repository: repo, privacy: PrivacyGuard(), settings: AppSettings.shared)
        board.clearContents(); board.setString("internal", forType: .string)
        monitor.ignore(changeCount: board.changeCount); monitor.poll()
        #expect(try repo.recent(limit: 10, filter: .all).isEmpty)
    }
}
