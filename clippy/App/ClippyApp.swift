//
//  ClippyApp.swift
//  clippy
//
//  Entry point. There is deliberately no WindowGroup: Clippy is a menu-bar
//  utility (LSUIElement = YES in Info.plist build settings), so its only
//  windows are the floating clipboard panel and the Settings window, both
//  created imperatively by AppController rather than by a SwiftUI Scene.
//

import SwiftUI

@main
struct ClippyApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var appController

    var body: some Scene {
        // An empty Settings scene keeps SwiftUI from complaining about a
        // Scene-less App while AppController manages the real Settings window.
        Settings {
            EmptyView()
        }
    }
}
