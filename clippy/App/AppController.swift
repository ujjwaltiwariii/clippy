//
//  AppController.swift
//  clippy
//
//  Long-lived AppKit coordinator: owns the status item, the global hotkey,
//  the floating clipboard panel, and paste-simulation/focus-restoration.
//  This intentionally lives outside SwiftUI's view lifecycle so none of it
//  gets torn down/recreated when views recompute.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private(set) var clipboardService: ClipboardService!
    private var statusItem: NSStatusItem?
    private var globalHotKey: GlobalHotKey?
    private var panel: ClipboardPanel?
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()

    /// The app that was frontmost right before our panel stole focus, so a
    /// selection can be pasted back into the app the user was actually using.
    private var previouslyFrontmostApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermissionIfNeeded()

        do {
            let database = try Database(fileURL: AppConstants.databaseURL)
            let repository = ClipboardRepository(database: database)
            clipboardService = ClipboardService(repository: repository, monitor: ClipboardMonitor())
        } catch {
            // Storage is unusable; surface it instead of crashing the app.
            let alert = NSAlert()
            alert.messageText = "Clippy couldn't start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        setupStatusItem()
        setupGlobalHotKey()
        observeRecentItemsForMenu()
    }

    /// Triggers the system Accessibility prompt the first time Clippy runs,
    /// so auto-paste can work without the user having to dig through
    /// Settings first. Safe to call every launch: once granted, macOS
    /// won't prompt again.
    private func requestAccessibilityPermissionIfNeeded() {
        PasteSimulator.isAccessibilityTrusted(prompt: true)
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clippy")
        item.button?.image?.isTemplate = true
        item.menu = buildMenu()
        statusItem = item
    }

    private func observeRecentItemsForMenu() {
        clipboardService.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.statusItem?.menu = self?.buildMenu() }
            .store(in: &cancellables)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Clipboard", action: #selector(openClipboardFromMenu), keyEquivalent: "v")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let recents = Array(clipboardService.items.prefix(3))
        if recents.isEmpty {
            let empty = NSMenuItem(title: "No recent items", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, recentItem) in recents.enumerated() {
                let title = recentItem.preview.isEmpty ? "(empty)" : String(recentItem.preview.prefix(48))
                let menuItem = NSMenuItem(title: title, action: #selector(copyRecentItem(_:)), keyEquivalent: index < 9 ? "\(index + 1)" : "")
                menuItem.target = self
                menuItem.representedObject = recentItem.id
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())

        let pauseItem = NSMenuItem(title: clipboardService.isPaused ? "Resume History" : "Pause History",
                                    action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Clippy", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openClipboardFromMenu() { showPanel() }

    @objc private func copyRecentItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = clipboardService.items.first(where: { $0.id == id }) else { return }
        clipboardService.copyToPasteboard(item)
    }

    @objc private func togglePause() { clipboardService.togglePause() }
    @objc private func clearHistory() { clipboardService.clearHistory(keepPinned: true) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettings() {
        if settingsWindowController == nil {
            let rootView = SettingsView(clipboardService: clipboardService) { [weak self] keyCode, modifiers in
                self?.updateGlobalHotKey(keyCode: keyCode, modifiers: modifiers)
            }
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Clippy Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 520, height: 420))
            settingsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    // MARK: - Global hotkey

    private func setupGlobalHotKey() {
        let defaults = UserDefaults.standard
        let keyCode = UInt32(defaults.object(forKey: DefaultsKey.hotKeyKeyCode) as? Int ?? Int(AppConstants.defaultHotKeyKeyCode))
        let modifiers = UInt32(defaults.object(forKey: DefaultsKey.hotKeyModifiers) as? Int ?? Int(AppConstants.defaultHotKeyModifiers))
        globalHotKey = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.togglePanel()
        }
    }

    /// Re-registers the hotkey after the user picks a new shortcut in Settings.
    func updateGlobalHotKey(keyCode: UInt32, modifiers: UInt32) {
        globalHotKey = nil
        globalHotKey = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Panel

    private func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        previouslyFrontmostApp = NSWorkspace.shared.frontmostApplication

        if panel == nil {
            panel = ClipboardPanel(clipboardService: clipboardService) { [weak self] item in
                self?.select(item)
            } onClose: { [weak self] in
                self?.restoreFocusToPreviousApp()
            }
        }
        panel?.presentCenteredOnActiveScreen()
    }

    private func hidePanel() {
        panel?.dismiss()
    }

    private func select(_ item: ClipboardItem) {
        clipboardService.copyToPasteboard(item)
        panel?.dismiss()
        restoreFocusToPreviousApp(thenPaste: true)
    }

    private func restoreFocusToPreviousApp(thenPaste: Bool = false) {
        guard let app = previouslyFrontmostApp else { return }
        app.activate(options: [])
        guard thenPaste else { return }
        // Give the target app a beat to actually become key before we
        // synthesize the keystroke into it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            PasteSimulator.simulatePasteIfPermitted()
        }
    }
}
