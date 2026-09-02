//
//  ClipboardView.swift
//  clippy
//
//  The Spotlight-style search + list content hosted inside ClipboardPanel.
//

import SwiftUI
import AppKit

struct ClipboardView: View {
    @ObservedObject var clipboardService: ClipboardService
    let onSelect: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    @State private var selectedID: UUID?
    @State private var eventMonitor: Any?

    private var groups: [(section: HistorySection, items: [ClipboardItem])] {
        SearchService.group(clipboardService.items)
    }
    private var flatItems: [ClipboardItem] { SearchService.flattenedOrder(clipboardService.items) }
    private var selectedItem: ClipboardItem? { flatItems.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()

            if flatItems.isEmpty {
                emptyState
            } else {
                listContent
                Divider()
                ClipboardPreview(item: selectedItem, imageProvider: clipboardService.imageData)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .top) { toast }
        .onAppear {
            selectedID = flatItems.first?.id
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: clipboardService.items) { _, newItems in
            let flattened = SearchService.flattenedOrder(newItems)
            if !flattened.contains(where: { $0.id == selectedID }) {
                selectedID = flattened.first?.id
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16))
            ClipboardSearchBar(text: Binding(
                get: { clipboardService.searchText },
                set: { clipboardService.updateSearch($0) }
            ), onSubmit: selectHighlighted)
            if clipboardService.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.section) { group in
                        Section {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { _, item in
                                let flatIndex = flatItems.firstIndex(where: { $0.id == item.id })
                                ClipboardItemRow(item: item,
                                                  isSelected: item.id == selectedID,
                                                  quickIndex: flatIndex,
                                                  imageProvider: clipboardService.imageData)
                                    .id(item.id)
                                    .onTapGesture { selectedID = item.id; onSelect(item) }
                                    .contextMenu { contextMenu(for: item) }
                            }
                        } header: {
                            Text(group.section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Clipboard is empty")
                .font(.headline)
            Text("Copy something and it will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    @ViewBuilder
    private var toast: some View {
        if let message = clipboardService.toastMessage {
            Text(message)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thickMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                        withAnimation { clipboardService.toastMessage = nil }
                    }
                }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button(item.isPinned ? "Unpin" : "Pin") { clipboardService.togglePin(item) }
        Button("Copy") { clipboardService.copyToPasteboard(item) }
        Divider()
        Button("Delete", role: .destructive) { clipboardService.delete(item) }
    }

    // MARK: - Keyboard

    private func selectHighlighted() {
        guard let item = selectedItem else { return }
        onSelect(item)
    }

    private func moveSelection(by delta: Int) {
        guard !flatItems.isEmpty else { return }
        let currentIndex = flatItems.firstIndex { $0.id == selectedID } ?? 0
        let newIndex = min(max(currentIndex + delta, 0), flatItems.count - 1)
        selectedID = flatItems[newIndex].id
    }

    private func installKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 125: moveSelection(by: 1); return true // Down
        case 126: moveSelection(by: -1); return true // Up
        case 36, 76: selectHighlighted(); return true // Return / keypad enter
        case 53: onDismiss(); return true // Escape
        case 51 where flags == .command: // Cmd+Delete
            if let item = selectedItem { clipboardService.delete(item) }
            return true
        default: break
        }

        if flags == .command, let characters = event.charactersIgnoringModifiers {
            if characters == "p", let item = selectedItem {
                clipboardService.togglePin(item)
                return true
            }
            if let digit = Int(characters), (1...9).contains(digit), digit - 1 < flatItems.count {
                onSelect(flatItems[digit - 1])
                return true
            }
        }
        return false
    }
}
