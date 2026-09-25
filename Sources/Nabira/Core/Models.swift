import AppKit
import Foundation

enum ClipboardContentType: String, Codable, CaseIterable, Sendable {
    case text, richText, html, url, image, files, color, unknown

    var label: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich Text"
        case .html: "HTML"
        case .url: "Link"
        case .image: "Image"
        case .files: "Files"
        case .color: "Color"
        case .unknown: "Item"
        }
    }
}

struct PasteboardRepresentation: Codable, Hashable, Sendable {
    let type: String
    let data: Data
}

struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var contentType: ClipboardContentType
    var searchableText: String
    var title: String
    var representations: [PasteboardRepresentation]
    var sourceBundleID: String?
    var sourceAppName: String?
    let firstCopiedAt: Date
    var lastCopiedAt: Date
    var copyCount: Int
    var byteCount: Int
    var isPinned: Bool
    var contentHash: String
    var pinnedOrder: Int?

    var plainText: String? {
        representations.first(where: { $0.type == NSPasteboard.PasteboardType.string.rawValue })
            .flatMap { String(data: $0.data, encoding: .utf8) } ??
        (contentType == .text || contentType == .url ? searchableText : nil)
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", text = "Text", links = "Links", images = "Images", files = "Files", pinned = "Pinned"
    var id: String { rawValue }
}

enum OTPBehavior: String, CaseIterable, Identifiable, Sendable {
    case ignore = "Never save"
    case expire = "Delete after 60 seconds"
    case keep = "Keep"
    var id: String { rawValue }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

enum TextTransformation: String, CaseIterable, Identifiable, Sendable {
    case plain = "Plain Text"
    case uppercase = "UPPERCASE"
    case lowercase = "lowercase"
    case capitalize = "Capitalize Words"
    case trim = "Trim Whitespace"
    case collapseSpaces = "Collapse Repeated Spaces"
    case removeEmptyLines = "Remove Empty Lines"
    case urlEncode = "URL Encode"
    case urlDecode = "URL Decode"
    case jsonPretty = "JSON Pretty Print"
    case jsonMinify = "JSON Minify"
    var id: String { rawValue }
}

enum NabiraError: LocalizedError {
    case database(String)
    case noPasteableContent
    case invalidTransformation

    var errorDescription: String? {
        switch self {
        case .database(let message): "Database error: \(message)"
        case .noPasteableContent: "This item has no pasteable content."
        case .invalidTransformation: "The text cannot be transformed."
        }
    }
}
