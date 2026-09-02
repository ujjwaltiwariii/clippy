//
//  AppConstants.swift
//  clippy
//
//  Central place for tunables so behavior isn't scattered as magic numbers.
//

import Foundation
import Carbon.HIToolbox

enum AppConstants {
    static let bundleIdentifier = "bhindi.cloud.clippy"
    static let appName = "Clippy"

    /// How often the pasteboard's changeCount is polled. NSPasteboard has no
    /// change notification API, so polling is the only reliable mechanism.
    static let pasteboardPollInterval: TimeInterval = 0.45

    static let defaultMaxHistoryItems = 500
    static let maxStoredTextLength = 200_000 // guard against pathological huge copies
    static let previewCharacterLimit = 400

    static let defaultHotKeyKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    static let defaultHotKeyModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var imagesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Images", isDirectory: true)
    }

    static var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("clipboard.sqlite")
    }
}

enum DefaultsKey {
    static let maxHistoryItems = "maxHistoryItems"
    static let autoDeleteAfter = "autoDeleteAfter"
    static let saveImages = "saveImages"
    static let saveFiles = "saveFiles"
    static let detectSensitiveContent = "detectSensitiveContent"
    static let autoDeleteOTP = "autoDeleteOTP"
    static let ignorePasswordManagers = "ignorePasswordManagers"
    static let isPaused = "isPaused"
    static let launchAtLogin = "launchAtLogin"
    static let appearance = "appearance"
    static let hotKeyKeyCode = "hotKeyKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let showMenuBarIcon = "showMenuBarIcon"
}

enum AutoDeleteInterval: Int, CaseIterable, Identifiable {
    case never = 0
    case oneHour = 3600
    case oneDay = 86_400
    case sevenDays = 604_800
    case thirtyDays = 2_592_000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never: return "Never"
        case .oneHour: return "1 hour"
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        }
    }
}

enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
