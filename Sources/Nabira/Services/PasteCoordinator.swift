import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteCoordinator: TextInserting {
    private let pasteboard: NSPasteboard
    private weak var monitor: ClipboardMonitor?
    private var targetApplication: NSRunningApplication?
    var onNotice: ((String) -> Void)?
    var onCopied: ((UUID) -> Void)?

    init(pasteboard: NSPasteboard = .general, monitor: ClipboardMonitor) {
        self.pasteboard = pasteboard
        self.monitor = monitor
    }

    func captureTarget() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        targetApplication = application
    }

    func paste(_ item: ClipboardItem, asPlainText: Bool) async -> PasteResult {
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
        onCopied?(item.id)

        guard AXIsProcessTrusted() else {
            onNotice?("Copied. Enable Accessibility in System Settings for direct paste.")
            return .copiedPermissionNeeded
        }
        guard let target = targetApplication else { return .failed("No target application") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            return .failed("The previous application is no longer active")
        }
        try? await Task.sleep(for: .milliseconds(50))

        guard postCommandV() else {
            return .failed("Could not send paste command")
        }
        return .inserted
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Address the permission pane by its identifier, regardless of its displayed name.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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

}
