//
//  ClipboardContent.swift
//  clippy
//
//  A type-safe abstraction over whatever NSPasteboard happened to contain,
//  rather than assuming everything is a plain string.
//

import Foundation
import AppKit

enum ClipboardContentType: String, Codable {
    case text
    case url
    case image
    case file
    case richText
    case unknown
}

/// A normalized snapshot of one pasteboard change, ready to be persisted or
/// written back to NSPasteboard.
struct ClipboardContent {
    let type: ClipboardContentType
    let plainText: String?
    let rtfData: Data?
    let htmlString: String?
    let imageData: Data?
    let fileURLs: [URL]?
    let sourceAppBundleID: String?
    let sourceAppName: String?

    /// The value used for hashing/de-duplication and for full-text search.
    var canonicalText: String {
        switch type {
        case .text, .url, .richText:
            return plainText ?? ""
        case .file:
            return (fileURLs ?? []).map(\.path).joined(separator: "\n")
        case .image:
            return imageData?.sha256Hex ?? UUID().uuidString
        case .unknown:
            return plainText ?? UUID().uuidString
        }
    }

    var contentHash: String {
        canonicalText.sha256Hex
    }

    var characterCount: Int {
        canonicalText.count
    }
}
