import AppKit
import Foundation

struct PrivacyGuard: PrivacyFiltering {
    func decision(for candidate: ClipboardCandidate, settings: SettingsSnapshot) -> PrivacyDecision {
        let maximumBytes = candidate.contentType == .image ? settings.maxImageBytes : settings.maxItemBytes
        if candidate.byteCount > maximumBytes { return .ignore("Item is too large") }
        return .allow
    }
}
