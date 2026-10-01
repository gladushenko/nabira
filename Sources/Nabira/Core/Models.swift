import AppKit
import Foundation

enum ClipboardContentType: String, Codable, CaseIterable, Sendable {
    case text, richText, html, url, image, files, color, unknown

    var label: String {
        switch self {
        case .text, .richText, .html: "Text"
        case .url: "Link"
        case .image: "Image"
        case .files: "Files"
        case .color: "Color"
        case .unknown: "Item"
        }
    }

    var canBePinned: Bool {
        self != .image && self != .files
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
    case all = "All", text = "Text", links = "Links", images = "Images", files = "Files", favorites = "Favorites"
    var id: String { rawValue }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

enum TextTransformation: String, CaseIterable, Identifiable, Sendable {
    case uppercase = "Uppercase"
    case lowercase = "Lowercase"
    case capitalize = "Capitalize Words"
    case collapseSpaces = "Normalize Whitespace"
    case spacesToUnderscores = "Spaces to Underscores"
    case urlEncode = "URL Encode"
    case urlDecode = "URL Decode"
    case jsonPretty = "JSON Pretty Print"
    case jsonMinify = "JSON Minify"
    var id: String { rawValue }

    var example: String {
        switch self {
        case .uppercase: "Nabira is awesome → NABIRA IS AWESOME"
        case .lowercase: "NABIRA IS AWESOME → nabira is awesome"
        case .capitalize: "nabira is awesome → Nabira Is Awesome"
        case .collapseSpaces: "  Nabira   is   awesome  → Nabira is awesome"
        case .spacesToUnderscores: "Nabira   is   awesome → Nabira_is_awesome"
        case .urlEncode: "Nabira is awesome → Nabira%20is%20awesome"
        case .urlDecode: "Nabira%20is%20awesome → Nabira is awesome"
        case .jsonPretty: "Compact JSON → indented JSON"
        case .jsonMinify: "Indented JSON → compact JSON"
        }
    }
}

enum NabiraError: LocalizedError {
    case database(String)
    case noPasteableContent
    case invalidTransformation
    case pinLimitReached(Int)

    var errorDescription: String? {
        switch self {
        case .database(let message): "Database error: \(message)"
        case .noPasteableContent: "This item has no pasteable content."
        case .invalidTransformation: "The text cannot be transformed."
        case .pinLimitReached(let limit): "You can add up to \(limit) items to Favorites."
        }
    }
}
