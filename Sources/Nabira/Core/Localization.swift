import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, english = "en", russian = "ru"

    var id: Self { self }

    func resolvedCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if self != .system { return rawValue }
        return Bundle.preferredLocalizations(from: ["en", "ru"], forPreferences: preferredLanguages).first ?? "en"
    }
}

struct AppLocalization: Sendable {
    let locale: Locale
    private let bundle: Bundle

    init(language: AppLanguage) {
        let code = language.resolvedCode()
        locale = Locale(identifier: code)
        // An explicit language bundle lets the in-app choice override the system language.
        bundle = Bundle.module.url(forResource: code, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? Bundle.module
    }

    func callAsFunction(_ value: String.LocalizationValue) -> String {
        // Resolve against the language injected by LocalizedContent, including plural rules.
        String(localized: value, bundle: bundle, locale: locale)
    }

    func key(_ value: String) -> String {
        bundle.localizedString(forKey: value, value: value, table: nil)
    }
}
