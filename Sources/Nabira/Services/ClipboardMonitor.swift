import AppKit
import Foundation

@MainActor
final class ClipboardMonitor: ClipboardCapturing {
    private let pasteboard: NSPasteboard
    private let repository: ClipboardRepository
    private let privacy: PrivacyFiltering
    private let settings: AppSettings
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCounts = Set<Int>()
    var onCapture: (@MainActor (ClipboardItem) -> Void)?

    init(pasteboard: NSPasteboard = .general, repository: ClipboardRepository, privacy: PrivacyFiltering, settings: AppSettings) {
        self.pasteboard = pasteboard
        self.repository = repository
        self.privacy = privacy
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }
    func ignore(changeCount: Int) { ignoredChangeCounts.insert(changeCount) }

    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if ignoredChangeCounts.remove(count) != nil { return }
        guard let item = pasteboard.pasteboardItems?.first else { return }

        let source = NSWorkspace.shared.frontmostApplication
        let representations = item.types.compactMap { type -> PasteboardRepresentation? in
            guard let data = item.data(forType: type) else { return nil }
            return PasteboardRepresentation(type: type.rawValue, data: data)
        }
        guard !representations.isEmpty else { return }
        let classified = Self.classify(item: item, representations: representations)
        let candidate = ClipboardCandidate(representations: representations, sourceBundleID: source?.bundleIdentifier,
                                           searchableText: classified.text, contentType: classified.type,
                                           byteCount: representations.reduce(0) { $0 + $1.data.count })
        let decision = privacy.decision(for: candidate, settings: settings.snapshot)
        guard decision != .ignore("") else { return }
        if case .ignore = decision { return }

        let now = Date()
        let title = Self.makeTitle(text: classified.text, type: classified.type)
        let captured = ClipboardItem(id: UUID(), contentType: classified.type, searchableText: classified.text,
                                     title: title, representations: representations, sourceBundleID: source?.bundleIdentifier,
                                     sourceAppName: source?.localizedName, firstCopiedAt: now, lastCopiedAt: now,
                                     copyCount: 1, byteCount: candidate.byteCount, isPinned: false,
                                     contentHash: ContentHasher.hash(representations), pinnedOrder: nil)
        do {
            let stored = try repository.upsert(captured)
            try repository.prune(maxItems: AppSettings.maxItems, olderThan: Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: now)!)
            onCapture?(stored)
            if case .expire(let delay) = decision {
                Task { [repository, id = stored.id] in
                    try? await Task.sleep(for: .seconds(delay))
                    try? repository.delete(id: id)
                }
            }
        } catch { NSLog("Nabira capture failed: %@", error.localizedDescription) }
    }

    static func classify(item: NSPasteboardItem, representations: [PasteboardRepresentation]) -> (type: ClipboardContentType, text: String) {
        if let fileURL = item.propertyList(forType: .fileURL) as? String {
            let path = URL(string: fileURL).flatMap { $0.isFileURL ? $0.path : nil } ?? fileURL
            return (.files, path)
        }
        if let url = item.string(forType: .URL) { return (.url, url) }
        if item.availableType(from: [.png, .tiff]) != nil { return (.image, "Image") }
        if let html = item.string(forType: .html) { return (.html, stripHTML(html)) }
        if let rtf = item.data(forType: .rtf), let value = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) { return (.richText, value.string) }
        if let text = item.string(forType: .string) {
            if URL(string: text)?.scheme != nil { return (.url, text) }
            if text.range(of: #"^(#?[0-9A-Fa-f]{6}|rgb\s*\()"#, options: .regularExpression) != nil { return (.color, text) }
            return (.text, text)
        }
        return (.unknown, representations.map(\.type).joined(separator: " "))
    }

    private static func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        else { return html }
        return attributed.string
    }

    private static func makeTitle(text: String, type: ClipboardContentType) -> String {
        let compact = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? type.label : String(compact.prefix(120))
    }
}
