//
//  ClipboardMonitor.swift
//  clippy
//
//  NSPasteboard has no change-notification API, so polling changeCount is
//  the standard, low-overhead way every clipboard manager (Maccy, Paste,
//  etc.) detects new copies. A short timer with tolerance keeps this cheap.
//

import Foundation
import AppKit

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    /// Set right after we write to the pasteboard ourselves, so our own
    /// paste-back doesn't get re-recorded as a "new" copy.
    private(set) var ignoredChangeCount: Int?

    var onNewContent: ((ClipboardContent) -> Void)?
    var isPaused = false

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: AppConstants.pasteboardPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = AppConstants.pasteboardPollInterval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markSelfWrite(changeCount: Int) {
        ignoredChangeCount = changeCount
        lastChangeCount = changeCount
    }

    private func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if let ignored = ignoredChangeCount, ignored == currentChangeCount {
            ignoredChangeCount = nil
            return
        }
        guard !isPaused else { return }
        guard let content = ClipboardReader.read(from: pasteboard) else { return }
        onNewContent?(content)
    }
}
