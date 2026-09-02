//
//  ClipboardWriter.swift
//  clippy
//

import Foundation
import AppKit

struct ClipboardWriter {
    /// Writes a stored item back onto the system pasteboard. Returns the
    /// pasteboard changeCount *after* writing, so the monitor can recognize
    /// this as a self-inflicted change and skip re-recording it.
    @discardableResult
    static func write(_ item: ClipboardItem, imageDataProvider: (ClipboardItem) -> Data?) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text, .url:
            pasteboard.setString(item.textContent ?? "", forType: .string)
        case .richText:
            pasteboard.setString(item.textContent ?? "", forType: .string)
            if let rtf = item.rtfData {
                pasteboard.setData(rtf, forType: .rtf)
            }
            if let html = item.htmlString?.data(using: .utf8) {
                pasteboard.setData(html, forType: .html)
            }
        case .image:
            if let data = imageDataProvider(item), let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file:
            let urls = (item.textContent ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
            pasteboard.writeObjects(urls as [NSPasteboardWriting])
        case .unknown:
            pasteboard.setString(item.textContent ?? "", forType: .string)
        }

        return pasteboard.changeCount
    }
}
