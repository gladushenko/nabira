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

private func repository() async throws -> SQLiteClipboardRepository {
    try await SQLiteClipboardRepository(path: FileManager.default.temporaryDirectory.appending(path: "nabira-\(UUID().uuidString).sqlite3").path)
}

@Suite struct NabiraTests {
    @Test func defaultClipboardShortcutIsCommandB() {
        #expect(GlobalShortcut.clipboardHistoryDefault.keyCode == 11)
        #expect(GlobalShortcut.clipboardHistoryDefault.displayName == "⌘B")
    }

    @MainActor @Test func historyLimitIsFixedAtThreeHundredItems() {
        #expect(AppSettings.maxItems == 300)
        #expect(AppSettings.maxPinnedItems == 10)
        #expect(AppSettings.defaultRetentionDays == 30)
        #expect(AppSettings.retentionOptions == [1, 7, 14, 30, 60])
        #expect(AppSettings.defaultClipboardEnabled)
        #expect(AppSettings.defaultShowClipboardPreviews)
        #expect(AppSettings.defaultClipboardDescriptionOptions == Set(ClipboardDescriptionOption.allCases))
        #expect(AppSettings.defaultShowAllClipboardDescriptions)
        #expect(AppSettings.defaultPasteOnSingleClick)
        #expect(AppSettings.maxHistoryBytes == 2 * 1_024 * 1_024 * 1_024)
        #expect(AppSettings.maxImageBytes == 100 * 1_024 * 1_024)
        #expect(AppSettings.shared.snapshot.maxItems == 300)
    }

    @Test func textFormatsShareTheTextLabel() {
        #expect(ClipboardContentType.text.label == "Text")
        #expect(ClipboardContentType.richText.label == "Text")
        #expect(ClipboardContentType.html.label == "Text")
        #expect(ClipboardContentType.url.label == "Link")
        #expect(makeItem("Nabira").characterCount == 6)

        var file = makeItem("/Users/example/file.txt")
        file.contentType = .files
        #expect(file.characterCount == nil)
    }

    @Test func deduplicatesAndUpdatesRecency() async throws {
        let repo = try await repository()
        let first = makeItem("same", date: Date(timeIntervalSince1970: 1))
        _ = try await repo.upsert(first)
        var second = makeItem("same", date: Date(timeIntervalSince1970: 2))
        second.contentHash = first.contentHash
        let stored = try await repo.upsert(second)
        #expect(try await repo.recent(limit: 10, filter: .all).count == 1)
        #expect(stored.copyCount == 2)
        #expect(stored.lastCopiedAt == second.lastCopiedAt)
    }

    @Test func pinnedItemsSurvivePruning() async throws {
        let repo = try await repository()
        let old = makeItem("old", date: Date(timeIntervalSince1970: 1))
        _ = try await repo.upsert(old)
        try await repo.setPinned(true, id: old.id)
        try await repo.prune(maxItems: 1, maxBytes: 1, olderThan: .now)
        #expect(try await repo.item(id: old.id) != nil)
    }

    @Test func pruningKeepsNewestItemsWithinStorageLimit() async throws {
        let repo = try await repository()
        let old = makeItem("12345", date: Date(timeIntervalSince1970: 1))
        let new = makeItem("67890", date: Date(timeIntervalSince1970: 2))
        _ = try await repo.upsert(old)
        _ = try await repo.upsert(new)

        try await repo.prune(maxItems: 10, maxBytes: 5, olderThan: .distantPast)

        #expect(try await repo.item(id: old.id) == nil)
        #expect(try await repo.item(id: new.id) != nil)
    }

    @Test func imagesAndFilesCannotBePinned() async throws {
        let repo = try await repository()
        for type in [ClipboardContentType.image, .files] {
            var item = makeItem(type.rawValue)
            item.contentType = type
            _ = try await repo.upsert(item)

            try await repo.setPinned(true, id: item.id)

            #expect(try await repo.item(id: item.id)?.isPinned == false)
        }
    }

    @Test func noMoreThanTenItemsCanBePinned() async throws {
        let repo = try await repository()
        for index in 0..<AppSettings.maxPinnedItems {
            let item = makeItem("pinned \(index)")
            _ = try await repo.upsert(item)
            try await repo.setPinned(true, id: item.id)
        }
        let extra = makeItem("one too many")
        _ = try await repo.upsert(extra)

        var reachedLimit = false
        do {
            try await repo.setPinned(true, id: extra.id)
        } catch NabiraError.pinLimitReached(let limit) {
            reachedLimit = limit == AppSettings.maxPinnedItems
        }

        #expect(reachedLimit)
        #expect(try await repo.item(id: extra.id)?.isPinned == false)
    }

    @Test func clearAllRemovesPinnedAndUnpinnedItems() async throws {
        let repo = try await repository()
        let pinned = makeItem("pinned")
        let unpinned = makeItem("unpinned")
        _ = try await repo.upsert(pinned)
        _ = try await repo.upsert(unpinned)
        try await repo.setPinned(true, id: pinned.id)

        try await repo.clear(since: nil, includePinned: true)

        #expect(try await repo.recent(limit: 10, filter: .all).isEmpty)
    }

    @Test func fullTextSearch() async throws {
        let repo = try await repository()
        _ = try await repo.upsert(makeItem("a surprisingly specific nebula phrase"))
        #expect(try await repo.search("nebula", filter: .all, limit: 10).count == 1)
        #expect(try await repo.search("missing", filter: .all, limit: 10).isEmpty)
    }

    @Test func captureGuardFiltersLargeItems() {
        let guardService = PrivacyGuard()
        let settings = SettingsSnapshot(maxItems: 5_000, retentionDays: 30, maxItemBytes: 10_000, maxImageBytes: 100_000)
        let rep = PasteboardRepresentation(type: "public.utf8-plain-text", data: Data("hello".utf8))
        #expect(guardService.decision(for: .init(representations: [rep], sourceBundleID: "blocked.app", searchableText: "hello", contentType: .text, byteCount: 5), settings: settings) == .allow)
        let secret = PasteboardRepresentation(type: "org.nspasteboard.ConcealedType", data: Data())
        #expect(guardService.decision(for: .init(representations: [secret], sourceBundleID: nil, searchableText: "secret", contentType: .text, byteCount: 0), settings: settings) == .allow)
        #expect(guardService.decision(for: .init(representations: [rep], sourceBundleID: nil, searchableText: "large text", contentType: .text, byteCount: 50_000), settings: settings) == .ignore("Item is too large"))
        #expect(guardService.decision(for: .init(representations: [rep], sourceBundleID: nil, searchableText: "image", contentType: .image, byteCount: 50_000), settings: settings) == .allow)
        #expect(guardService.decision(for: .init(representations: [rep], sourceBundleID: nil, searchableText: "123456", contentType: .text, byteCount: 6), settings: settings) == .allow)
    }

    @Test func textTransformations() async throws {
        let transformer = TextTransformer()
        #expect(try await transformer.transform("  a   b  ", using: .collapseSpaces) == "a b")
        #expect(try await transformer.transform("  Nabira   is   awesome  ", using: .spacesToUnderscores) == "Nabira_is_awesome")
        #expect(try await transformer.transform("{\"b\":2,\"a\":1}", using: .jsonMinify) == "{\"a\":1,\"b\":2}")
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

    @MainActor @Test func selfCaptureChangeCountCanBeIgnored() async throws {
        let board = NSPasteboard(name: .init("NabiraTests-\(UUID())"))
        let repo = try await repository()
        let monitor = ClipboardMonitor(pasteboard: board, repository: repo, privacy: PrivacyGuard(), settings: AppSettings.shared)
        board.clearContents(); board.setString("internal", forType: .string)
        monitor.ignore(changeCount: board.changeCount); await monitor.poll()
        #expect(try await repo.recent(limit: 10, filter: .all).isEmpty)
    }
}
