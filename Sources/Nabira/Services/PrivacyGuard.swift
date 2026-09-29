import AppKit
import Foundation

struct PrivacyGuard: PrivacyFiltering {
    private static let concealedMarkers = ["concealed", "transient", "password", "private"]

    func decision(for candidate: ClipboardCandidate, settings: SettingsSnapshot) -> PrivacyDecision {
        if let bundleID = candidate.sourceBundleID, settings.excludedBundleIDs.contains(bundleID) {
            return .ignore("Excluded application")
        }
        let types = Set(candidate.representations.map(\.type))
        if !types.isDisjoint(with: settings.ignoredPasteboardTypes) ||
            types.contains(where: { type in Self.concealedMarkers.contains(where: { type.localizedCaseInsensitiveContains($0) }) }) {
            return .ignore("Private pasteboard type")
        }
        if candidate.byteCount > settings.maxItemBytes { return .ignore("Item is too large") }
        if Self.looksLikeOTP(candidate.searchableText) {
            switch settings.otpBehavior {
            case .ignore: return .ignore("Likely one-time code")
            case .expire: return .expire(after: 60)
            case .keep: break
            }
        }
        return .allow
    }

    static func looksLikeOTP(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil else { return false }
        return !trimmed.hasPrefix("0") || trimmed.count == 6
    }
}
