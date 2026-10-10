import Foundation
import Testing

@testable import Nabira

@Suite struct LocalizationTests {
    @Test func compiledCatalogSupportsBothLanguages() {
        let english = AppLocalization(language: .english)
        let russian = AppLocalization(language: .russian)
        #expect(english("Language") == "Language")
        #expect(russian("Language") == "Язык")
        #expect(russian.key("General") == "Основные")
        #expect(russian("Version \("0.1.0")") == "Версия 0.1.0")
        #expect(russian.key("A missing translation") == "A missing translation")
    }

    @Test func russianCharacterCountsUsePluralRules() {
        let russian = AppLocalization(language: .russian)
        for (count, expected) in [(1, "1 символ"), (2, "2 символа"), (5, "5 символов"),
                                  (11, "11 символов"), (21, "21 символ"), (22, "22 символа")] {
            #expect(russian("\(count) chars") == expected)
        }
        let english = AppLocalization(language: .english)
        #expect(english("\(1) chars") == "1 char")
        #expect(english("\(2) chars") == "2 chars")
    }

    @Test func systemLanguageUsesPreferredSupportedLanguage() {
        #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["ru-RU", "en-US"]) == "ru")
        #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["en-GB", "ru-RU"]) == "en")
        #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["de-DE"]) == "en")
        #expect(AppLanguage.english.resolvedCode(preferredLanguages: ["ru-RU"]) == "en")
    }

    @MainActor @Test func languageChoicePersistsAndInvalidValuesUseSystem() {
        let name = "NabiraLocalizationTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.language == .system)
        settings.language = .russian
        #expect(AppSettings(defaults: defaults).language == .russian)
        settings.language = .english
        #expect(AppSettings(defaults: defaults).language == .english)
        defaults.set("unsupported", forKey: "language")
        #expect(AppSettings(defaults: defaults).language == .system)
    }
}
