//
//  Extensions.swift
//  clippy
//

import Foundation
import CryptoKit
import AppKit

extension Data {
    /// Stable content hash used for de-duplicating clipboard entries.
    var sha256Hex: String {
        let digest = SHA256.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    var sha256Hex: String {
        Data(utf8).sha256Hex
    }

    /// A short single-line preview safe for list rows.
    func makePreview(limit: Int = AppConstants.previewCharacterLimit) -> String {
        let collapsed = replacingOccurrences(of: "\n", with: " ⏎ ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= limit { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<index]) + "…"
    }
}

extension Date {
    /// Buckets a timestamp into the sections the history list groups by.
    func historySection(relativeTo now: Date = Date()) -> HistorySection {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return .today }
        if calendar.isDateInYesterday(self) { return .yesterday }
        if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now), self >= sevenDaysAgo {
            return .previous7Days
        }
        return .older
    }

    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

enum HistorySection: Int, CaseIterable, Comparable {
    case pinned = 0
    case today
    case yesterday
    case previous7Days
    case older

    static func < (lhs: HistorySection, rhs: HistorySection) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .pinned: return "Pinned"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .previous7Days: return "Previous 7 Days"
        case .older: return "Older"
        }
    }
}

extension NSImage {
    /// Downscales large screenshots before they're written to disk as thumbnails/originals.
    func resized(maxDimension: CGFloat) -> NSImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension, largestSide > 0 else { return self }
        let scale = maxDimension / largestSide
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    var pngData: Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
