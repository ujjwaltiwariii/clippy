//
//  LaunchAtLoginManager.swift
//  clippy
//
//  Wraps SMAppService (macOS 13+) — the modern replacement for the old
//  SMLoginItemSetEnabled / shared-file-list login item hacks.
//

import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return true }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
