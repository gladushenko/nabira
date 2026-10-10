import SwiftUI

extension EnvironmentValues {
    @Entry var appLocalization = AppLocalization(language: .system)
}

struct LocalizedContent<Content: View>: View {
    @Bindable var settings: AppSettings
    let content: Content

    var body: some View {
        let localization = AppLocalization(language: settings.language)
        content
            .environment(\.locale, localization.locale)
            .environment(\.appLocalization, localization)
    }
}
