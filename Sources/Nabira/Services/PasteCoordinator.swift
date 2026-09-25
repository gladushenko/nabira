import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteCoordinator: TextInserting {
    private let pasteboard: NSPasteboard
    private weak var monitor: ClipboardMonitor?
    private let settings: AppSettings
    var targetApplication: NSRunningApplication?
    private var targetAccessibilityApplication: AXUIElement?
    private var targetFocusedElement: AXUIElement?
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

        let accessibilityApplication = AXUIElementCreateApplication(application.processIdentifier)
        targetAccessibilityApplication = accessibilityApplication
        var focusedElement: CFTypeRef?
        if AXUIElementCopyAttributeValue(accessibilityApplication, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
           let focusedElement {
            targetFocusedElement = (focusedElement as! AXUIElement)
        } else {
            targetFocusedElement = nil
        }
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
        target.activate(options: [.activateAllWindows])
        if let targetAccessibilityApplication {
            AXUIElementSetAttributeValue(targetAccessibilityApplication, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        for _ in 0..<20 where !target.isActive {
            try? await Task.sleep(for: .milliseconds(25))
        }
        if let targetFocusedElement {
            AXUIElementSetAttributeValue(targetFocusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        try? await Task.sleep(for: .milliseconds(100))

        if let text = item.plainText {
            guard let targetFocusedElement,
                  AXUIElementSetAttributeValue(targetFocusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else {
                return .failed("Could not insert text into the focused field")
            }
            if settings.restoreClipboard {
                restore(backup)
                monitor?.ignore(changeCount: pasteboard.changeCount)
            }
            return .inserted
        }

        postCommandV()
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

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
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
