import AppKit

@MainActor
final class AppServices {
    let settings = AppSettings.shared
    let repository: SQLiteClipboardRepository
    let monitor: ClipboardMonitor
    let pasteCoordinator: PasteCoordinator
    let libraryModel: HistoryViewModel
    let shortcuts = GlobalShortcutManager()

    init() async throws {
        let support = try AppInfo.dataDirectory()
        repository = try await SQLiteClipboardRepository(path: support.appending(path: "history.sqlite3").path)
        monitor = ClipboardMonitor(repository: repository, privacy: PrivacyGuard(), settings: settings)
        pasteCoordinator = PasteCoordinator(monitor: monitor)
        libraryModel = HistoryViewModel(repository: repository, pasteCoordinator: pasteCoordinator)
        try await monitor.pruneHistory()
        settings.onRetentionDaysChange = { [weak monitor, weak libraryModel] in
            Task {
                do {
                    try await monitor?.pruneHistory()
                    libraryModel?.reload()
                } catch { libraryModel?.errorMessage = error.localizedDescription }
            }
        }
        monitor.onCapture = { [weak libraryModel] item in
            libraryModel?.lastCopiedItemID = item.id
            libraryModel?.reload()
        }
    }
}
