import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let repository: ClipboardRepository
    private let privacy: PrivacyFiltering
    private let settings: AppSettings
    private var timer: Timer?
    private var isPolling = false
    private var lastChangeCount: Int
    private var ignoredChangeCounts = Set<Int>()
    var onCapture: (@MainActor (ClipboardItem) -> Void)?

    init(
        pasteboard: NSPasteboard = .general, repository: ClipboardRepository, privacy: PrivacyFiltering,
        settings: AppSettings
    ) {
        self.pasteboard = pasteboard
        self.repository = repository
        self.privacy = privacy
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
    func ignore(changeCount: Int) { ignoredChangeCounts.insert(changeCount) }

    func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let shouldIgnore = ignoredChangeCounts.contains(count)
        ignoredChangeCounts = ignoredChangeCounts.filter { $0 > count }
        if shouldIgnore { return }
        guard let items = pasteboard.pasteboardItems, let item = items.first else { return }

        let source = NSWorkspace.shared.frontmostApplication
        let representations = items.enumerated().flatMap { index, item in
            item.types.compactMap { type -> PasteboardRepresentation? in
                guard let data = item.data(forType: type) else { return nil }
                var representation = PasteboardRepresentation(type: type.rawValue, data: data)
                representation.itemIndex = items.count > 1 ? index : nil
                return representation
            }
        }
        guard !representations.isEmpty else { return }
        let classified = Self.classify(item: item, representations: representations)
        let searchableText =
            classified.type == .files
            ? items.map { Self.classify(item: $0, representations: []).text }.joined(separator: "\n")
            : classified.text
        let candidate = ClipboardCandidate(
            representations: representations, sourceBundleID: source?.bundleIdentifier,
            searchableText: searchableText, contentType: classified.type,
            byteCount: representations.reduce(0) { $0 + $1.data.count })
        let decision = privacy.decision(for: candidate, settings: settings.snapshot)
        if case .ignore = decision { return }

        let now = Date()
        let captured = ClipboardItem(
            id: UUID(), contentType: classified.type, searchableText: searchableText,
            title: classified.type.label, representations: representations, sourceBundleID: source?.bundleIdentifier,
            sourceAppName: source?.localizedName, firstCopiedAt: now, lastCopiedAt: now,
            copyCount: 1, byteCount: candidate.byteCount, isPinned: false,
            contentHash: "", pinnedOrder: nil)
        do {
            let stored = try await repository.upsert(captured)
            try await pruneHistory()
            onCapture?(stored)
            if case .expire(let delay) = decision {
                Task { [repository, id = stored.id] in
                    do {
                        try await Task.sleep(for: .seconds(delay))
                        try Task.checkCancellation()
                        try await repository.delete(id: id)
                    } catch { /* Cancellation or expiration failure leaves the item intact. */  }
                }
            }
        } catch { NSLog("Nabira capture failed: %@", error.localizedDescription) }
    }

    func pruneHistory() async throws {
        let olderThan = Date().addingTimeInterval(-Double(settings.retentionDays) * 86_400)
        try await repository.prune(
            maxItems: AppSettings.maxItems,
            maxBytes: AppSettings.maxHistoryBytes,
            olderThan: olderThan
        )
    }

    static func classify(item: NSPasteboardItem, representations: [PasteboardRepresentation]) -> (
        type: ClipboardContentType, text: String
    ) {
        if let fileURL = item.propertyList(forType: .fileURL) as? String {
            let path = URL(string: fileURL).flatMap { $0.isFileURL ? $0.path : nil } ?? fileURL
            return (.files, path)
        }
        if let url = item.string(forType: .URL) { return (.url, url) }
        if item.availableType(from: [.png, .tiff]) != nil { return (.image, "Image") }
        if let html = item.string(forType: .html) {
            return (.html, item.string(forType: .string) ?? stripHTML(html))
        }
        if item.availableType(from: [.rtf]) != nil, let text = item.string(forType: .string) {
            return (.richText, text)
        }
        if let rtf = item.data(forType: .rtf),
            let value = try? NSAttributedString(
                data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        {
            return (.richText, value.string)
        }
        if let text = item.string(forType: .string) {
            if URL(string: text)?.scheme != nil { return (.url, text) }
            if text.range(of: #"^(#?[0-9A-Fa-f]{6}|rgb\s*\()"#, options: .regularExpression) != nil {
                return (.color, text)
            }
            return (.text, text)
        }
        return (.unknown, representations.map(\.type).joined(separator: " "))
    }

    private static func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
            let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ], documentAttributes: nil)
        else { return html }
        return attributed.string
    }

}
