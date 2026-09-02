//
//  ClipboardRepository.swift
//  clippy
//
//  Maps ClipboardItem <-> SQLite rows and owns de-duplication / retention
//  policy. All methods are safe to call from any thread; they hop onto a
//  background queue internally and never touch the database on the caller's
//  thread.
//

import Foundation
import SQLite3

protocol ClipboardRepositoryProtocol {
    func insertOrBump(_ content: ClipboardContent, isSensitive: Bool) async throws -> ClipboardItem
    func fetchAll(limit: Int) async throws -> [ClipboardItem]
    func search(query: String, limit: Int) async throws -> [ClipboardItem]
    func setPinned(_ id: UUID, pinned: Bool) async throws
    func delete(_ id: UUID) async throws
    func clearAll(keepPinned: Bool) async throws
    func purgeExpired(after interval: TimeInterval) async throws
    func imageData(for item: ClipboardItem) -> Data?
}

final class ClipboardRepository: ClipboardRepositoryProtocol {
    private let database: Database
    private let backgroundQueue = DispatchQueue(label: "bhindi.cloud.clippy.repository", qos: .utility)

    init(database: Database) {
        self.database = database
        try? FileManager.default.createDirectory(at: AppConstants.imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Write path

    func insertOrBump(_ content: ClipboardContent, isSensitive: Bool) async throws -> ClipboardItem {
        let hash = content.contentHash
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            backgroundQueue.async { [self] in
                do {
                    if let existingID = try findID(byHash: hash) {
                        try touch(id: existingID)
                    } else {
                        try insert(content, hash: hash, isSensitive: isSensitive)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        guard let item = try await fetchByHash(hash) else {
            throw ClipboardError.databaseFailure("Failed to read back inserted item")
        }
        return item
    }

    private func fetchByHash(_ hash: String) async throws -> ClipboardItem? {
        try await Task.detached(priority: .userInitiated) { [database] in
            try database.perform { handle in
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                sqlite3_prepare_v2(handle, "SELECT * FROM clipboard_items WHERE content_hash = ? LIMIT 1;", -1, &statement, nil)
                Database.bind(statement, text: hash, at: 1)
                return Self.readRows(statement).first
            }
        }.value
    }

    private func findID(byHash hash: String) throws -> UUID? {
        try database.perform { handle in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            sqlite3_prepare_v2(handle, "SELECT id FROM clipboard_items WHERE content_hash = ? LIMIT 1;", -1, &statement, nil)
            Database.bind(statement, text: hash, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW, let idString = Database.columnText(statement, 0) else {
                return nil
            }
            return UUID(uuidString: idString)
        }
    }

    private func touch(id: UUID) throws {
        try database.perform { handle in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            sqlite3_prepare_v2(handle, "UPDATE clipboard_items SET updated_at = ? WHERE id = ?;", -1, &statement, nil)
            sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
            Database.bind(statement, text: id.uuidString, at: 2)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ClipboardError.databaseFailure("touch failed")
            }
        }
    }

    private func insert(_ content: ClipboardContent, hash: String, isSensitive: Bool) throws {
        var imageFileName: String?
        if content.type == .image, let data = content.imageData {
            let name = "\(UUID().uuidString).png"
            let url = AppConstants.imagesDirectory.appendingPathComponent(name)
            try? data.write(to: url)
            imageFileName = name
        }

        let id = UUID()
        let now = Date().timeIntervalSince1970
        let preview = isSensitive ? "Sensitive content" : content.canonicalText.makePreview()
        let textToStore: String?
        if isSensitive {
            textToStore = nil
        } else {
            switch content.type {
            case .file: textToStore = (content.fileURLs ?? []).map(\.path).joined(separator: "\n")
            default: textToStore = content.plainText
            }
        }

        try database.perform { handle in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            sqlite3_prepare_v2(handle, """
                INSERT INTO clipboard_items
                (id, type, text_content, rtf_data, html_string, image_file_name,
                 source_app_bundle_id, source_app_name, content_hash, preview,
                 character_count, created_at, updated_at, is_pinned, is_sensitive)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?);
                """, -1, &statement, nil)
            Database.bind(statement, text: id.uuidString, at: 1)
            Database.bind(statement, text: content.type.rawValue, at: 2)
            Database.bind(statement, text: textToStore, at: 3)
            Database.bind(statement, data: isSensitive ? nil : content.rtfData, at: 4)
            Database.bind(statement, text: isSensitive ? nil : content.htmlString, at: 5)
            Database.bind(statement, text: imageFileName, at: 6)
            Database.bind(statement, text: content.sourceAppBundleID, at: 7)
            Database.bind(statement, text: content.sourceAppName, at: 8)
            Database.bind(statement, text: hash, at: 9)
            Database.bind(statement, text: preview, at: 10)
            sqlite3_bind_int64(statement, 11, Int64(content.characterCount))
            sqlite3_bind_double(statement, 12, now)
            sqlite3_bind_double(statement, 13, now)
            sqlite3_bind_int(statement, 14, isSensitive ? 1 : 0)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ClipboardError.databaseFailure("insert failed")
            }
        }
    }

    // MARK: - Read path

    func fetchAll(limit: Int) async throws -> [ClipboardItem] {
        try await Task.detached(priority: .userInitiated) { [database] in
            try database.perform { handle in
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                sqlite3_prepare_v2(handle, """
                    SELECT * FROM clipboard_items
                    ORDER BY is_pinned DESC, updated_at DESC LIMIT ?;
                    """, -1, &statement, nil)
                sqlite3_bind_int64(statement, 1, Int64(limit))
                return Self.readRows(statement)
            }
        }.value
    }

    func search(query: String, limit: Int) async throws -> [ClipboardItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return try await fetchAll(limit: limit)
        }
        let likeQuery = "%\(query)%"
        return try await Task.detached(priority: .userInitiated) { [database] in
            try database.perform { handle in
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                sqlite3_prepare_v2(handle, """
                    SELECT * FROM clipboard_items
                    WHERE (text_content LIKE ? OR preview LIKE ?) AND is_sensitive = 0
                    ORDER BY is_pinned DESC, updated_at DESC LIMIT ?;
                    """, -1, &statement, nil)
                Database.bind(statement, text: likeQuery, at: 1)
                Database.bind(statement, text: likeQuery, at: 2)
                sqlite3_bind_int64(statement, 3, Int64(limit))
                return Self.readRows(statement)
            }
        }.value
    }

    private static func readRows(_ statement: OpaquePointer?) -> [ClipboardItem] {
        var results: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idString = columnText(statement, 0),
                  let id = UUID(uuidString: idString),
                  let typeString = columnText(statement, 1),
                  let type = ClipboardContentType(rawValue: typeString) else { continue }
            let item = ClipboardItem(
                id: id,
                type: type,
                textContent: columnText(statement, 2),
                rtfData: Database.columnData(statement, 3),
                htmlString: columnText(statement, 4),
                imageFileName: columnText(statement, 5),
                sourceAppBundleID: columnText(statement, 6),
                sourceAppName: columnText(statement, 7),
                contentHash: columnText(statement, 8) ?? "",
                preview: columnText(statement, 9) ?? "",
                characterCount: Int(sqlite3_column_int64(statement, 10)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 12)),
                isPinned: sqlite3_column_int(statement, 13) != 0,
                isSensitive: sqlite3_column_int(statement, 14) != 0
            )
            results.append(item)
        }
        return results
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        Database.columnText(statement, index)
    }

    // MARK: - Mutations

    func setPinned(_ id: UUID, pinned: Bool) async throws {
        try await Task.detached(priority: .userInitiated) { [database] in
            try database.perform { handle in
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                sqlite3_prepare_v2(handle, "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?;", -1, &statement, nil)
                sqlite3_bind_int(statement, 1, pinned ? 1 : 0)
                Database.bind(statement, text: id.uuidString, at: 2)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw ClipboardError.databaseFailure("pin update failed")
                }
            }
        }.value
    }

    func delete(_ id: UUID) async throws {
        if let item = try await fetchAll(limit: 10_000).first(where: { $0.id == id }),
           let fileName = item.imageFileName {
            try? FileManager.default.removeItem(at: AppConstants.imagesDirectory.appendingPathComponent(fileName))
        }
        try await Task.detached(priority: .userInitiated) { [database] in
            try database.perform { handle in
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                sqlite3_prepare_v2(handle, "DELETE FROM clipboard_items WHERE id = ?;", -1, &statement, nil)
                Database.bind(statement, text: id.uuidString, at: 1)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw ClipboardError.databaseFailure("delete failed")
                }
            }
        }.value
    }

    func clearAll(keepPinned: Bool) async throws {
        let items = try await fetchAll(limit: 100_000)
        for item in items where !(keepPinned && item.isPinned) {
            if let fileName = item.imageFileName {
                try? FileManager.default.removeItem(at: AppConstants.imagesDirectory.appendingPathComponent(fileName))
            }
        }
        try await Task.detached(priority: .utility) { [database] in
            try database.perform { handle in
                let sql = keepPinned ? "DELETE FROM clipboard_items WHERE is_pinned = 0;" : "DELETE FROM clipboard_items;"
                if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
                    throw ClipboardError.databaseFailure(String(cString: sqlite3_errmsg(handle)))
                }
            }
        }.value
    }

    func purgeExpired(after interval: TimeInterval) async throws {
        guard interval > 0 else { return }
        let cutoff = Date().addingTimeInterval(-interval).timeIntervalSince1970
        let expiring = try await fetchAll(limit: 100_000).filter { !$0.isPinned && $0.updatedAt.timeIntervalSince1970 < cutoff }
        for item in expiring {
            if let fileName = item.imageFileName {
                try? FileManager.default.removeItem(at: AppConstants.imagesDirectory.appendingPathComponent(fileName))
            }
        }
        try await Task.detached(priority: .utility) { [database] in
            try database.perform { handle in
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                sqlite3_prepare_v2(handle, "DELETE FROM clipboard_items WHERE is_pinned = 0 AND updated_at < ?;", -1, &statement, nil)
                sqlite3_bind_double(statement, 1, cutoff)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw ClipboardError.databaseFailure("purge failed")
                }
            }
        }.value
    }

    func imageData(for item: ClipboardItem) -> Data? {
        guard let fileName = item.imageFileName else { return nil }
        return try? Data(contentsOf: AppConstants.imagesDirectory.appendingPathComponent(fileName))
    }
}
