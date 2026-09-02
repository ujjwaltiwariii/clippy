//
//  ClipboardItemRow.swift
//  clippy
//

import SwiftUI
import AppKit

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let quickIndex: Int?
    let imageProvider: (ClipboardItem) -> Data?

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(item.isSensitive ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(item.updatedAt.relativeDescription)
                    if item.isPinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .labelStyle(.iconOnly)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let quickIndex, quickIndex < 9 {
                Text("⌘\(quickIndex + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
        }
        .contentShape(Rectangle())
    }

    private var displayTitle: String {
        item.isSensitive ? "Sensitive content" : item.preview
    }

    @ViewBuilder
    private var iconView: some View {
        if item.isSensitive {
            Image(systemName: "lock.fill")
                .foregroundStyle(isSelected ? .white : .orange)
        } else {
            switch item.type {
            case .image:
                if let data = imageProvider(item), let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            case .url:
                Image(systemName: "link")
                    .foregroundStyle(isSelected ? .white : .blue)
            case .file:
                Image(systemName: "doc")
                    .foregroundStyle(isSelected ? .white : .secondary)
            case .richText:
                Image(systemName: "textformat")
                    .foregroundStyle(isSelected ? .white : .purple)
            case .text, .unknown:
                Image(systemName: "text.alignleft")
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
        }
    }
}
