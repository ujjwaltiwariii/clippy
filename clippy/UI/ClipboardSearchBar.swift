//
//  ClipboardSearchBar.swift
//  clippy
//

import SwiftUI
import AppKit

/// A NSViewRepresentable-backed text field so we can reliably force first
/// responder status the instant the panel appears — SwiftUI's own
/// @FocusState occasionally loses the race against the panel's fade-in.
struct ClipboardSearchBar: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusableTextField()
        field.placeholderString = "Search clipboard…"
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitted)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: ClipboardSearchBar
        init(_ parent: ClipboardSearchBar) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        @objc func submitted() { parent.onSubmit() }
    }
}

/// Ensures Tab/Return don't get swallowed by the field editor's default
/// beep-on-unhandled-command behavior inside a borderless panel.
private final class FocusableTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
}
