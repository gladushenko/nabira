import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteCoordinator: TextInserting {
    private let pasteboard: NSPasteboard
    private weak var monitor: ClipboardMonitor?
    private let settings: AppSettings
    private var targetApplication: NSRunningApplication?
    var onNotice: ((String) -> Void)?

    init(pasteboard: NSPasteboard = .general, monitor: ClipboardMonitor, settings: AppSettings) {
        self.pasteboard = pasteboard
        self.monitor = monitor
        self.settings = settings
    }

    func captureTarget() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        targetApplication = application
    }

    func paste(_ item: ClipboardItem, asPlainText: Bool) async -> PasteResult {
        let backup = captureCurrentPasteboard()
        pasteboard.clearContents()
        if asPlainText {
            guard let text = item.plainText else { return .failed("No text representation") }
            pasteboard.setString(text, forType: .string)
        } else {
            let output = NSPasteboardItem()
            for representation in item.representations {
                output.setData(representation.data, forType: .init(representation.type))
            }
            guard pasteboard.writeObjects([output]) else { return .failed("Could not write pasteboard") }
        }
        monitor?.ignore(changeCount: pasteboard.changeCount)

        guard AXIsProcessTrusted() else {
            onNotice?("Copied. Enable Accessibility in System Settings for direct paste.")
            return .copiedPermissionNeeded
        }
        guard let target = targetApplication else { return .failed("No target application") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            return .failed("The previous application is no longer active")
        }
        try? await Task.sleep(for: .milliseconds(150))

        guard postCommandV() else {
            return .failed("Could not send paste command")
        }
        if settings.restoreClipboard {
            try? await Task.sleep(for: .milliseconds(350))
            restore(backup)
            monitor?.ignore(changeCount: pasteboard.changeCount)
        }
        return .inserted
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let commandFlag = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        down.flags = commandFlag
        up.flags = commandFlag
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func captureCurrentPasteboard() -> [PasteboardRepresentation] {
        pasteboard.pasteboardItems?.first?.types.compactMap { type in
            pasteboard.data(forType: type).map { PasteboardRepresentation(type: type.rawValue, data: $0) }
        } ?? []
    }

    private func restore(_ values: [PasteboardRepresentation]) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        values.forEach { item.setData($0.data, forType: .init($0.type)) }
        pasteboard.writeObjects([item])
    }
}
