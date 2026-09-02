//
//  ClipboardItem.swift
//  clippy
//
//  The persisted, UI-facing representation of one clipboard history entry.
//

import Foundation

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    var type: ClipboardContentType
    /// Plain text content, a URL string, a rich-text plain fallback, or
    /// newline-joined file paths — interpretation depends on `type`.
    var textContent: String?
    var rtfData: Data?
    var htmlString: String?
    /// Relative filename inside AppConstants.imagesDirectory, for `.image` items.
    var imageFileName: String?
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var contentHash: String
    var preview: String
    var characterCount: Int
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isSensitive: Bool

    var section: HistorySection {
        isPinned ? .pinned : updatedAt.historySection()
    }
}
