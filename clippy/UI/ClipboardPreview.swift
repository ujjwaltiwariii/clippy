//
//  ClipboardPreview.swift
//  clippy
//
//  Larger detail preview for the currently highlighted row, shown along the
//  bottom of the panel — mirrors the "big preview" pattern in Alfred/Raycast.
//

import SwiftUI
import AppKit

struct ClipboardPreview: View {
    let item: ClipboardItem?
    let imageProvider: (ClipboardItem) -> Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item {
                HStack {
                    Text(item.sourceAppName ?? "Unknown app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(item.characterCount) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                ScrollView {
                    contentView(for: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Clipboard is empty")
                        .font(.headline)
                    Text("Copy something and it will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(14)
        .frame(height: 140)
    }

    @ViewBuilder
    private func contentView(for item: ClipboardItem) -> some View {
        if item.isSensitive {
            Label("Sensitive content is hidden", systemImage: "lock.fill")
                .foregroundStyle(.orange)
        } else {
            switch item.type {
            case .image:
                if let data = imageProvider(item), let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 100)
                } else {
                    Text("Image unavailable")
                }
            default:
                Text(item.textContent ?? item.preview)
                    .font(.system(size: 12, design: item.type == .text ? .monospaced : .default))
                    .textSelection(.enabled)
            }
        }
    }
}
