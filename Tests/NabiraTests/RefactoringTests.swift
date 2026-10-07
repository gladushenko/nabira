import AppKit
import CSQLite
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Nabira

@Suite struct RefactoringTests {
    private func item(_ text: String, date: Date = .now) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), contentType: .text, searchableText: text, title: text,
            representations: [.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))],
            sourceBundleID: nil, sourceAppName: nil, firstCopiedAt: date, lastCopiedAt: date,
            copyCount: 1, byteCount: text.utf8.count, isPinned: false, contentHash: "", pinnedOrder: nil
        )
    }

    private func repository() async throws -> SQLiteClipboardRepository {
        try await SQLiteClipboardRepository(path: ":memory:")
    }

    @MainActor private func settings() -> AppSettings {
        // An isolated suite keeps regression tests away from the user's preferences.
        AppSettings(defaults: UserDefaults(suiteName: "NabiraTests-\(UUID())")!)
    }

    @Test func legacyRepresentationsRemainReadable() throws {
        let data = Data(#"[{"type":"public.utf8-plain-text","data":"aGVsbG8="}]"#.utf8)
        let representations = try JSONDecoder().decode([PasteboardRepresentation].self, from: data)
        #expect(representations.first?.itemIndex == nil)
        #expect(String(decoding: representations[0].data, as: UTF8.self) == "hello")
        let explicitZero = PasteboardRepresentation(
            type: representations[0].type, data: representations[0].data, itemIndex: 0)
        #expect(ContentHasher.hash(representations) == ContentHasher.hash([explicitZero]))
    }

    @MainActor @Test func richTextCaptureUsesTheProvidedPlainTextRepresentation() {
        let item = NSPasteboardItem()
        item.setString("<b>HTML content</b>", forType: .html)
        item.setString("Provided plain text", forType: .string)
        let classified = ClipboardMonitor.classify(item: item, representations: [])
        #expect(classified.type == .html)
        #expect(classified.text == "Provided plain text")
    }

    @Test func listsLoadMetadataAndDetailsPreservePayload() async throws {
        let repository = try await repository()
        let stored = try await repository.upsert(item("searchable payload"))
        let recent = try await repository.recent(limit: 10)
        let search = try await repository.search("searchable")
        #expect(recent.count == 1)
        #expect(recent[0].representations.isEmpty)
        #expect(!recent[0].hasLoadedRepresentations)
        #expect(recent[0].plainText == "searchable payload")
        #expect(search[0].representations.isEmpty)
        let details = try #require(try await repository.item(id: stored.id))
        #expect(details.hasLoadedRepresentations)
        #expect(details.representations == stored.representations)
    }

    @MainActor @Test func multipleFilesRoundTripThroughCaptureStorageAndPaste() async throws {
        let board = NSPasteboard(name: .init("NabiraTests-\(UUID())"))
        defer { board.releaseGlobally() }
        let repository = try await repository()
        let monitor = ClipboardMonitor(
            pasteboard: board, repository: repository, privacy: PrivacyGuard(), settings: settings())
        let urls = ["file:///tmp/first.txt", "file:///tmp/second.txt"]
        let inputs = urls.map { url in
            let item = NSPasteboardItem()
            item.setString(url, forType: .fileURL)
            return item
        }
        board.clearContents()
        #expect(board.writeObjects(inputs))
        await monitor.poll()
        let summary = try #require(try await repository.recent(limit: 10).first)
        let captured = try #require(try await repository.item(id: summary.id))
        #expect(captured.searchableText == "/tmp/first.txt\n/tmp/second.txt")
        #expect(Set(captured.representations.compactMap(\.itemIndex)) == [0, 1])
        let coordinator = PasteCoordinator(pasteboard: board, monitor: monitor, isAccessibilityTrusted: { false })
        _ = await coordinator.paste(captured, asPlainText: false)
        #expect(board.pasteboardItems?.compactMap { $0.string(forType: .fileURL) } == urls)
        await monitor.poll()
        #expect(try await repository.recent(limit: 10).count == 1)

        var merged = captured
        merged.representations = captured.representations.map { representation in
            var representation = representation
            representation.itemIndex = nil
            return representation
        }
        #expect(ContentHasher.hash(merged.representations) != captured.contentHash)
    }

    @MainActor @Test func focusChangeDuringPasteDelayDoesNotSendCommand() async throws {
        let repository = try await repository()
        let board = NSPasteboard(name: .init("NabiraTests-\(UUID())"))
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(
            pasteboard: board, repository: repository, privacy: PrivacyGuard(), settings: settings())
        var currentPID: pid_t = 123
        var sent = false
        let coordinator = PasteCoordinator(
            pasteboard: board, monitor: monitor,
            frontmostProcessID: { currentPID }, isAccessibilityTrusted: { true },
            sendPasteCommand: {
                sent = true
                return true
            },
            waitForPaste: { currentPID = 456 }
        )
        coordinator.captureTarget()
        let result = await coordinator.paste(item("hello"), asPlainText: false)
        if case .failed = result {} else { Issue.record("Expected paste failure after focus changed") }
        #expect(!sent)
        #expect(board.string(forType: .string) == "hello")
    }

    @MainActor @Test func cancellationDuringPasteDelayDoesNotSendCommand() async throws {
        let repository = try await repository()
        let board = NSPasteboard(name: .init("NabiraTests-\(UUID())"))
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(
            pasteboard: board, repository: repository, privacy: PrivacyGuard(), settings: settings())
        var sent = false
        let coordinator = PasteCoordinator(
            pasteboard: board, monitor: monitor,
            frontmostProcessID: { 123 }, isAccessibilityTrusted: { true },
            sendPasteCommand: {
                sent = true
                return true
            },
            waitForPaste: { throw CancellationError() }
        )
        coordinator.captureTarget()
        let result = await coordinator.paste(item("hello"), asPlainText: false)
        if case .failed = result {} else { Issue.record("Expected cancelled paste to fail") }
        #expect(!sent)
    }

    @MainActor @Test func invalidPlainTextPastePreservesExistingClipboard() async throws {
        let repository = try await repository()
        let board = NSPasteboard(name: .init("NabiraTests-\(UUID())"))
        defer { board.releaseGlobally() }
        board.setString("existing", forType: .string)
        let monitor = ClipboardMonitor(
            pasteboard: board, repository: repository, privacy: PrivacyGuard(), settings: settings())
        let coordinator = PasteCoordinator(pasteboard: board, monitor: monitor, isAccessibilityTrusted: { false })
        var image = item("image")
        image.contentType = .image
        image.representations = []
        _ = await coordinator.paste(image, asPlainText: true)
        #expect(board.string(forType: .string) == "existing")
    }

    @MainActor @Test func retentionPruningWorksWithoutNewClipboardCapture() async throws {
        let repository = try await repository()
        let settings = settings()
        settings.retentionDays = 30
        let old = try await repository.upsert(item("old", date: .now.addingTimeInterval(-40 * 86_400)))
        let recent = try await repository.upsert(item("recent", date: .now.addingTimeInterval(-10 * 86_400)))
        let favorite = try await repository.upsert(item("favorite", date: .now.addingTimeInterval(-50 * 86_400)))
        try await repository.setPinned(true, id: favorite.id)
        let monitor = ClipboardMonitor(repository: repository, privacy: PrivacyGuard(), settings: settings)
        try await monitor.pruneHistory()
        #expect(try await repository.item(id: old.id) == nil)
        #expect(try await repository.item(id: recent.id) != nil)
        settings.retentionDays = 1
        try await monitor.pruneHistory()
        #expect(try await repository.item(id: recent.id) == nil)
        #expect(try await repository.item(id: favorite.id)?.isPinned == true)
    }

    @MainActor @Test func cancelledSearchDoesNotReplaceNewerResults() async throws {
        let repository = try await repository()
        try await repository.upsert(item("first"))
        try await repository.upsert(item("second"))
        let monitor = ClipboardMonitor(repository: repository, privacy: PrivacyGuard(), settings: settings())
        let model = HistoryViewModel(repository: repository, pasteCoordinator: PasteCoordinator(monitor: monitor))
        model.query = "first"
        let firstLoad = model.reload()
        model.query = "second"
        let secondLoad = model.reload()
        await secondLoad.value
        await firstLoad.value
        #expect(model.items.map(\.searchableText) == ["second"])
    }

    @MainActor @Test func overlappingPasteRequestsOnlySendTheLatestCommand() async throws {
        let repository = try await repository()
        let board = NSPasteboard(name: .init("NabiraTests-\(UUID())"))
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(
            pasteboard: board, repository: repository, privacy: PrivacyGuard(), settings: settings())
        var delayedPaste: CheckedContinuation<Void, Never>?
        var sentCount = 0
        var didWait = false
        let coordinator = PasteCoordinator(
            pasteboard: board, monitor: monitor,
            frontmostProcessID: { 123 }, isAccessibilityTrusted: { true },
            sendPasteCommand: {
                sentCount += 1
                return true
            },
            waitForPaste: {
                if !didWait {
                    didWait = true
                    await withCheckedContinuation { delayedPaste = $0 }
                }
            }
        )
        coordinator.captureTarget()
        let firstPaste = Task { await coordinator.paste(item("first"), asPlainText: false) }
        while delayedPaste == nil { await Task.yield() }
        let latest = await coordinator.paste(item("second"), asPlainText: false)
        delayedPaste?.resume()
        let first = await firstPaste.value
        if case .inserted = latest {} else { Issue.record("Latest paste should succeed") }
        if case .failed = first {} else { Issue.record("Superseded paste should fail") }
        #expect(sentCount == 1)
        #expect(board.string(forType: .string) == "second")
    }

    @Test func imageListPreviewsAreDownsampledAndKeepOriginalPayload() async throws {
        let repository = try await repository()
        let context = try #require(
            CGContext(
                data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let image = try #require(context.makeImage())
        let payload = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(payload, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        var captured = item("Image")
        captured.contentType = .image
        captured.representations = [.init(type: NSPasteboard.PasteboardType.png.rawValue, data: payload as Data)]
        let stored = try await repository.upsert(captured)
        let thumbnail = try #require(try await repository.previewImage(id: stored.id))
        let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let preview = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(preview.width == 140)
        #expect(preview.height <= 140)
        #expect(try await repository.previewImage(id: stored.id) == thumbnail)
        #expect(try await repository.item(id: stored.id)?.representations == captured.representations)
    }

    @Test func sqliteStepErrorsAreThrownInsteadOfReturningEmptyHistory() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "NabiraTests-\(UUID()).sqlite3").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repository = try await SQLiteClipboardRepository(path: path)
        try await repository.upsert(item("hello"))
        var connection: OpaquePointer?
        #expect(sqlite3_open(path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        let sql = """
            ALTER TABLE clipboard_items RENAME TO original_items;
            CREATE VIEW clipboard_items AS SELECT id, content_type, searchable_text,
              abs(-9223372036854775808) AS title, representations, source_bundle_id,
              source_app_name, first_copied_at, last_copied_at, copy_count, byte_count,
              is_pinned, content_hash, pinned_order FROM original_items;
            """
        #expect(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
        do {
            _ = try await repository.recent(limit: 10)
            Issue.record("SQLite integer overflow must throw")
        } catch {
            #expect(error.localizedDescription.contains("integer overflow"))
        }
    }
}
