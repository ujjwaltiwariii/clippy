//
//  SearchService.swift
//  clippy
//
//  Groups an already-fetched, already-filtered item list into the sections
//  the history list renders. The actual text filtering happens in SQL
//  (ClipboardRepository.search) so it scales to a large history; this just
//  handles presentation-level ordering.
//

import Foundation

enum SearchService {
    static func group(_ items: [ClipboardItem]) -> [(section: HistorySection, items: [ClipboardItem])] {
        let grouped = Dictionary(grouping: items, by: \.section)
        return HistorySection.allCases
            .compactMap { section -> (HistorySection, [ClipboardItem])? in
                guard let bucket = grouped[section], !bucket.isEmpty else { return nil }
                return (section, bucket)
            }
    }

    /// Flat, selection-order list matching what's rendered — used for
    /// arrow-key navigation and the ⌘1…⌘9 quick-select shortcuts.
    static func flattenedOrder(_ items: [ClipboardItem]) -> [ClipboardItem] {
        group(items).flatMap(\.items)
    }
}
