import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteCoordinator {
    private let pasteboard: NSPasteboard
    private weak var monitor: ClipboardMonitor?
    private var targetProcessID: pid_t?
    private var pasteGeneration = 0
    private let frontmostProcessID: () -> pid_t?
    private let isAccessibilityTrusted: () -> Bool
    private let sendPasteCommand: () -> Bool
    private let waitForPaste: () async throws -> Void
    var onNotice: ((String) -> Void)?
    var onCopied: ((UUID) -> Void)?

    init(
        pasteboard: NSPasteboard = .general,
        monitor: ClipboardMonitor,
        frontmostProcessID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        sendPasteCommand: @escaping () -> Bool = { PasteCoordinator.postCommandV() },
        waitForPaste: @escaping () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) }
    ) {
        self.pasteboard = pasteboard
        self.monitor = monitor
        self.frontmostProcessID = frontmostProcessID
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.sendPasteCommand = sendPasteCommand
        self.waitForPaste = waitForPaste
    }

    func captureTarget() {
        guard let processID = frontmostProcessID(),
            processID != ProcessInfo.processInfo.processIdentifier
        else { return }
        targetProcessID = processID
    }

    func paste(_ item: ClipboardItem, asPlainText: Bool) async -> PasteResult {
        guard !Task.isCancelled else { return .failed("Paste cancelled") }
        pasteGeneration += 1
        let generation = pasteGeneration
        let output: [NSPasteboardItem]
        if asPlainText {
            guard let text = item.plainText else { return .failed("No text representation") }
            let textItem = NSPasteboardItem()
            guard textItem.setString(text, forType: .string) else { return .failed("Could not prepare text") }
            output = [textItem]
        } else {
            let groups = Dictionary(grouping: item.representations) { $0.itemIndex ?? 0 }
            guard !groups.isEmpty else { return .failed("No pasteable content") }
            output = groups.keys.sorted().map { index in
                let output = NSPasteboardItem()
                for representation in groups[index] ?? [] {
                    output.setData(representation.data, forType: .init(representation.type))
                }
                return output
            }
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(output) else { return .failed("Could not write pasteboard") }
        monitor?.ignore(changeCount: pasteboard.changeCount)
        onCopied?(item.id)

        guard isAccessibilityTrusted() else {
            onNotice?("Copied. Enable Accessibility in System Settings for direct paste.")
            return .copiedPermissionNeeded
        }
        guard let target = targetProcessID else { return .failed("No target application") }
        guard frontmostProcessID() == target else {
            return .failed("The previous application is no longer active")
        }
        do {
            try await waitForPaste()
            try Task.checkCancellation()
        } catch { return .failed("Paste cancelled") }
        guard frontmostProcessID() == target else {
            return .failed("The previous application is no longer active")
        }

        guard generation == pasteGeneration else { return .failed("Paste superseded") }
        guard sendPasteCommand() else {
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

    private static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return false }
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
