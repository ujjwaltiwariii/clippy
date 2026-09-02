//
//  SettingsView.swift
//  clippy
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject var clipboardService: ClipboardService
    var onHotKeyChanged: (UInt32, UInt32) -> Void = { _, _ in }

    var body: some View {
        TabView {
            GeneralSettingsTab(onHotKeyChanged: onHotKeyChanged)
                .tabItem { Label("General", systemImage: "gearshape") }

            ClipboardSettingsTab(clipboardService: clipboardService)
                .tabItem { Label("Clipboard", systemImage: "list.bullet.clipboard") }

            PrivacySettingsTab(clipboardService: clipboardService)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 480, height: 380)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(DefaultsKey.launchAtLogin) private var launchAtLoginPreference = LaunchAtLoginManager.isEnabled
    @AppStorage(DefaultsKey.showMenuBarIcon) private var showMenuBarIcon = true
    var onHotKeyChanged: (UInt32, UInt32) -> Void

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLoginPreference)
                .onChange(of: launchAtLoginPreference) { _, newValue in
                    LaunchAtLoginManager.setEnabled(newValue)
                }

            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)

            LabeledContent("Global Shortcut") {
                HotKeyRecorderField(onChanged: onHotKeyChanged)
            }

            AccessibilityPermissionRow()
        }
        .padding(.top, 8)
    }
}

private struct AccessibilityPermissionRow: View {
    @State private var isTrusted = PasteSimulator.isAccessibilityTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isTrusted ? .green : .orange)
                Text(isTrusted ? "Auto-paste is enabled" : "Auto-paste needs Accessibility access")
                    .font(.callout)
            }
            Text("Without this permission, Clippy still copies the selected item to your clipboard — you'll just need to press ⌘V yourself.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isTrusted {
                Button("Open Accessibility Settings") {
                    PasteSimulator.openAccessibilitySettings()
                }
            }
        }
        .onAppear { isTrusted = PasteSimulator.isAccessibilityTrusted() }
    }
}

/// Captures the next keyDown as the new global shortcut.
private struct HotKeyRecorderField: View {
    var onChanged: (UInt32, UInt32) -> Void
    @State private var isRecording = false
    @State private var displayString = HotKeyRecorderField.currentDisplayString()

    var body: some View {
        Button(isRecording ? "Press a key combo…" : displayString) {
            isRecording = true
        }
        .background(KeyCaptureView(isRecording: $isRecording) { keyCode, modifiers in
            UserDefaults.standard.set(Int(keyCode), forKey: DefaultsKey.hotKeyKeyCode)
            UserDefaults.standard.set(Int(modifiers), forKey: DefaultsKey.hotKeyModifiers)
            displayString = Self.displayString(keyCode: keyCode, modifiers: modifiers)
            onChanged(keyCode, modifiers)
        })
    }

    static func currentDisplayString() -> String {
        let defaults = UserDefaults.standard
        let keyCode = UInt32(defaults.object(forKey: DefaultsKey.hotKeyKeyCode) as? Int ?? Int(AppConstants.defaultHotKeyKeyCode))
        let modifiers = UInt32(defaults.object(forKey: DefaultsKey.hotKeyModifiers) as? Int ?? Int(AppConstants.defaultHotKeyModifiers))
        return displayString(keyCode: keyCode, modifiers: modifiers)
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += KeyCodeNaming.name(for: keyCode)
        return result
    }
}

private struct KeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = { keyCode, modifiers in
            onCapture(keyCode, modifiers)
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class CaptureView: NSView {
        var onCapture: ((UInt32, UInt32) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            var carbonModifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
            guard carbonModifiers != 0 else { return } // require at least one modifier
            onCapture?(UInt32(event.keyCode), carbonModifiers)
        }
    }
}

private enum KeyCodeNaming {
    static func name(for keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

// MARK: - Clipboard

private struct ClipboardSettingsTab: View {
    @ObservedObject var clipboardService: ClipboardService

    var body: some View {
        Form {
            Stepper(value: Binding(
                get: { clipboardService.settings.maxHistoryItems },
                set: { clipboardService.settings.maxHistoryItems = $0; clipboardService.persistSettings() }
            ), in: 50...5000, step: 50) {
                Text("Maximum history items: \(clipboardService.settings.maxHistoryItems)")
            }

            Picker("Automatically delete old items", selection: Binding(
                get: { clipboardService.settings.autoDeleteAfter },
                set: { clipboardService.settings.autoDeleteAfter = $0; clipboardService.persistSettings() }
            )) {
                ForEach(AutoDeleteInterval.allCases) { interval in
                    Text(interval.label).tag(interval.rawValue)
                }
            }

            Toggle("Save images", isOn: Binding(
                get: { clipboardService.settings.saveImages },
                set: { clipboardService.settings.saveImages = $0; clipboardService.persistSettings() }
            ))

            Toggle("Save files", isOn: Binding(
                get: { clipboardService.settings.saveFiles },
                set: { clipboardService.settings.saveFiles = $0; clipboardService.persistSettings() }
            ))

            Button("Clear All History", role: .destructive) {
                clipboardService.clearHistory(keepPinned: false)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Privacy

private struct PrivacySettingsTab: View {
    @ObservedObject var clipboardService: ClipboardService

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Don't store sensitive clipboard items", isOn: Binding(
                    get: { clipboardService.settings.dontStoreSensitiveItems },
                    set: { clipboardService.settings.dontStoreSensitiveItems = $0; clipboardService.persistSettings() }
                ))
                Toggle("Detect sensitive content (JWTs, API keys, cards…)", isOn: Binding(
                    get: { clipboardService.settings.detectSensitiveContent },
                    set: { clipboardService.settings.detectSensitiveContent = $0; clipboardService.persistSettings() }
                ))
                Toggle("Automatically delete OTP codes", isOn: Binding(
                    get: { clipboardService.settings.autoDeleteOTP },
                    set: { clipboardService.settings.autoDeleteOTP = $0; clipboardService.persistSettings() }
                ))
                Toggle("Ignore password managers", isOn: Binding(
                    get: { clipboardService.settings.ignorePasswordManagers },
                    set: { clipboardService.settings.ignorePasswordManagers = $0; clipboardService.persistSettings() }
                ))
                Toggle("Pause clipboard history", isOn: Binding(
                    get: { clipboardService.isPaused },
                    set: { _ in clipboardService.togglePause() }
                ))
            }

            Text("Detection is heuristic, not perfect — always double-check before sharing your clipboard history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @AppStorage(DefaultsKey.appearance) private var appearanceRawValue = AppearanceMode.system.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceRawValue) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: appearanceRawValue) { _, newValue in
                applyAppearance(AppearanceMode(rawValue: newValue) ?? .system)
            }
        }
        .padding(.top, 8)
        .onAppear { applyAppearance(AppearanceMode(rawValue: appearanceRawValue) ?? .system) }
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(AppConstants.appName)
                .font(.title2.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Text("100% local. No accounts, no analytics, no cloud sync. Your clipboard history never leaves this Mac.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
    }
}
