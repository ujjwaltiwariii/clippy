//
//  Database.swift
//  clippy
//
//  Thin, serial-queue wrapper around SQLite3's C API. All access is funneled
//  through one dedicated queue so the (non-thread-safe by default) SQLite
//  connection is never touched from two threads at once, and callers never
//  block the main thread.
//

import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Database {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "bhindi.cloud.clippy.database")

    init(fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(fileURL.path, &db) == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw ClipboardError.databaseFailure(message)
        }
        handle = db
        try execute("""
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                text_content TEXT,
                rtf_data BLOB,
                html_string TEXT,
                image_file_name TEXT,
                source_app_bundle_id TEXT,
                source_app_name TEXT,
                content_hash TEXT NOT NULL,
                preview TEXT NOT NULL,
                character_count INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                is_sensitive INTEGER NOT NULL DEFAULT 0
            );
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_content_hash ON clipboard_items(content_hash);")
        try execute("CREATE INDEX IF NOT EXISTS idx_updated_at ON clipboard_items(updated_at);")
    }

    deinit {
        sqlite3_close(handle)
    }

    private func execute(_ sql: String) throws {
        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            throw ClipboardError.databaseFailure(String(cString: sqlite3_errmsg(handle)))
        }
    }

    /// Runs `work` synchronously on the database's private serial queue.
    /// Callers on the main thread should wrap this with `Task.detached` or
    /// call it from an already-background context.
    func perform<T>(_ work: @escaping (OpaquePointer?) throws -> T) throws -> T {
        try queue.sync {
            try work(handle)
        }
    }

    static func bind(_ statement: OpaquePointer?, text: String?, at index: Int32) {
        if let text {
            sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func bind(_ statement: OpaquePointer?, data: Data?, at index: Int32) {
        if let data, !data.isEmpty {
            data.withUnsafeBytes { raw in
                _ = sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(data.count), sqliteTransient)
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    static func columnData(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }
}
