//
//  PasteSimulator.swift
//  clippy
//
//  Synthesizing a ⌘V keystroke into another app requires Accessibility
//  permission. When it isn't granted we still succeed at the core job
//  (the item is on the pasteboard) — we just can't auto-press paste.
//

import Foundation
import AppKit

enum PasteSimulator {
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func simulatePasteIfPermitted() -> Bool {
        guard isAccessibilityTrusted() else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return true
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
