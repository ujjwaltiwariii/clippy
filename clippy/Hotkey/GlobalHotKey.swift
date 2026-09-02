//
//  GlobalHotKey.swift
//  clippy
//
//  Registers a truly global keyboard shortcut using the Carbon Event
//  Manager's RegisterEventHotKey. Unlike NSEvent global monitors, this does
//  NOT require Accessibility permission, and it works no matter which app
//  is frontmost — it's the same mechanism Spotlight-style launchers use.
//
//  Ownership matters: this must be owned by a long-lived object (AppController),
//  not created inside a SwiftUI View's body, or the registration will be
//  torn down and re-created unpredictably as views recompute.
//

import Foundation
import Carbon.HIToolbox
import AppKit

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID: EventHotKeyID
    private let handler: () -> Void

    /// A process-wide incrementing ID so multiple GlobalHotKey instances
    /// (present + future) never collide.
    private static var nextID: UInt32 = 1

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.hotKeyID = EventHotKeyID(signature: OSType(fourCharCode("clpy")), id: Self.nextID)
        Self.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            var receivedID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &receivedID)
            let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            if receivedID.id == instance.hotKeyID.id {
                instance.handler()
            }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)

        guard installStatus == noErr else { return nil }

        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                  GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

private func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + scalar.value
    }
    return result
}
