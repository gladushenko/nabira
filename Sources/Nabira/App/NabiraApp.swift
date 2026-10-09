import AppKit

@main
enum NabiraApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // WindowCoordinator owns all windows; a SwiftUI Settings scene would create a second one.
        withExtendedLifetime(delegate) { application.run() }
    }
}
