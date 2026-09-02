//
//  ClipboardWindow.swift
//  clippy
//
//  A borderless, non-activating floating panel that hosts the SwiftUI
//  search UI — the Spotlight/Raycast-style presentation the spec calls for.
//

import AppKit
import SwiftUI

@MainActor
final class ClipboardPanel: NSPanel {
    private let onSelect: (ClipboardItem) -> Void
    private let onClose: () -> Void
    private var isDismissing = false

    private static let panelSize = NSSize(width: 640, height: 480)

    init(clipboardService: ClipboardService, onSelect: @escaping (ClipboardItem) -> Void, onClose: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onClose = onClose

        super.init(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                    styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                    backing: .buffered,
                    defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let rootView = ClipboardView(clipboardService: clipboardService,
                                      onSelect: { [weak self] item in self?.onSelect(item) },
                                      onDismiss: { [weak self] in self?.dismiss() })
        let hosting = NSHostingController(rootView: rootView)
        contentViewController = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func presentCenteredOnActiveScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - Self.panelSize.width / 2,
            y: screenFrame.midY - Self.panelSize.height / 2 + screenFrame.height * 0.12
        )
        setFrame(NSRect(origin: origin, size: Self.panelSize), display: false)

        alphaValue = 0
        setFrame(NSRect(origin: origin, size: Self.panelSize).insetBy(dx: 8, dy: 8), display: false)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(NSRect(origin: origin, size: Self.panelSize), display: true)
        }
    }

    func dismiss() {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            self.isDismissing = false
            self.onClose()
        })
    }

    override func resignKey() {
        super.resignKey()
        // Clicking away from the panel dismisses it, like Spotlight.
        dismiss()
    }
}
