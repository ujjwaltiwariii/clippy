//
//  ClipboardReader.swift
//  clippy
//
//  Turns whatever is currently on NSPasteboard.general into a ClipboardContent.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

enum ClipboardError: Error, LocalizedError {
    case unsupportedContent
    case databaseFailure(String)
    case pasteboardFailure
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .unsupportedContent: return "This clipboard content type isn't supported."
        case .databaseFailure(let reason): return "Clipboard history storage error: \(reason)"
        case .pasteboardFailure: return "Couldn't read the system clipboard."
        case .permissionDenied: return "Clippy doesn't have the permission it needs for that action."
        }
    }
}

struct ClipboardReader {
    /// The frontmost app is captured *before* we touch the pasteboard so
    /// we know who actually produced the copy (and so we can restore focus
    /// to it later when pasting).
    static func currentFrontmostApp() -> (bundleID: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }

    static func read(from pasteboard: NSPasteboard = .general) -> ClipboardContent? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        let front = currentFrontmostApp()

        // File URLs take priority: Finder puts a plain-text path *and* a
        // file URL on the pasteboard, so checking files first avoids
        // misclassifying a Finder copy as a text item.
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                                  options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            return ClipboardContent(type: .file, plainText: nil, rtfData: nil, htmlString: nil,
                                     imageData: nil, fileURLs: fileURLs,
                                     sourceAppBundleID: front.bundleID, sourceAppName: front.name)
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            let bounded = image.resized(maxDimension: 2000)
            guard let data = bounded.pngData else { return nil }
            return ClipboardContent(type: .image, plainText: nil, rtfData: nil, htmlString: nil,
                                     imageData: data, fileURLs: nil,
                                     sourceAppBundleID: front.bundleID, sourceAppName: front.name)
        }

        let rtfData = pasteboard.data(forType: .rtf)
        let htmlData = pasteboard.data(forType: .html)
        let htmlString = htmlData.flatMap { String(data: $0, encoding: .utf8) }
        let plain = pasteboard.string(forType: .string)

        if let plain, let url = URL(string: plain), url.scheme != nil, plain.contains("://") {
            return ClipboardContent(type: .url, plainText: plain, rtfData: rtfData, htmlString: htmlString,
                                     imageData: nil, fileURLs: nil,
                                     sourceAppBundleID: front.bundleID, sourceAppName: front.name)
        }

        if rtfData != nil || htmlString != nil, let plain, !plain.isEmpty {
            return ClipboardContent(type: .richText, plainText: plain, rtfData: rtfData, htmlString: htmlString,
                                     imageData: nil, fileURLs: nil,
                                     sourceAppBundleID: front.bundleID, sourceAppName: front.name)
        }

        if let plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let truncated = String(plain.prefix(AppConstants.maxStoredTextLength))
            return ClipboardContent(type: .text, plainText: truncated, rtfData: nil, htmlString: nil,
                                     imageData: nil, fileURLs: nil,
                                     sourceAppBundleID: front.bundleID, sourceAppName: front.name)
        }

        return nil
    }
}
