import CSQLite
import Foundation

final class SQLiteClipboardRepository: ClipboardRepository, SearchProviding, @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw NabiraError.database("Unable to open \(path)")
        }
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON;")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS clipboard_items (
          id TEXT PRIMARY KEY, content_type TEXT NOT NULL, searchable_text TEXT NOT NULL,
          title TEXT NOT NULL, representations BLOB NOT NULL, source_bundle_id TEXT,
          source_app_name TEXT, first_copied_at REAL NOT NULL, last_copied_at REAL NOT NULL,
          copy_count INTEGER NOT NULL, byte_count INTEGER NOT NULL, is_pinned INTEGER NOT NULL DEFAULT 0,
          content_hash TEXT NOT NULL UNIQUE, pinned_order INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_items_recent ON clipboard_items(is_pinned DESC, last_copied_at DESC);
        CREATE INDEX IF NOT EXISTS idx_items_type ON clipboard_items(content_type);
        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(
          id UNINDEXED, searchable_text, title, source_app_name, tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON clipboard_items BEGIN
          INSERT INTO clipboard_fts(id, searchable_text, title, source_app_name)
          VALUES (new.id, new.searchable_text, new.title, coalesce(new.source_app_name, ''));
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON clipboard_items BEGIN
          DELETE FROM clipboard_fts WHERE id = old.id;
        END;
        CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON clipboard_items BEGIN
          DELETE FROM clipboard_fts WHERE id = old.id;
          INSERT INTO clipboard_fts(id, searchable_text, title, source_app_name)
          VALUES (new.id, new.searchable_text, new.title, coalesce(new.source_app_name, ''));
        END;
        UPDATE clipboard_items
        SET is_pinned=0, pinned_order=NULL
        WHERE content_type IN ('image','files') AND is_pinned=1;
        """)
    }

    @discardableResult
    func upsert(_ item: ClipboardItem) throws -> ClipboardItem {
        try locked {
            if let existing = try fetchOne("SELECT * FROM clipboard_items WHERE content_hash = ?", binds: [.text(item.contentHash)]) {
                let sql = "UPDATE clipboard_items SET last_copied_at=?, copy_count=copy_count+1, source_bundle_id=?, source_app_name=? WHERE id=?"
                try run(sql, binds: [.double(item.lastCopiedAt.timeIntervalSince1970), .optionalText(item.sourceBundleID), .optionalText(item.sourceAppName), .text(existing.id.uuidString)])
                return try fetchOne("SELECT * FROM clipboard_items WHERE id=?", binds: [.text(existing.id.uuidString)]) ?? existing
            }
            let blob = try encoder.encode(item.representations)
            try run("""
                INSERT INTO clipboard_items(id,content_type,searchable_text,title,representations,source_bundle_id,source_app_name,first_copied_at,last_copied_at,copy_count,byte_count,is_pinned,content_hash,pinned_order)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, binds: [
                    .text(item.id.uuidString), .text(item.contentType.rawValue), .text(item.searchableText), .text(item.title), .blob(blob),
                    .optionalText(item.sourceBundleID), .optionalText(item.sourceAppName), .double(item.firstCopiedAt.timeIntervalSince1970),
                    .double(item.lastCopiedAt.timeIntervalSince1970), .int(item.copyCount), .int(item.byteCount), .int(item.isPinned ? 1 : 0),
                    .text(item.contentHash), item.pinnedOrder.map(Bind.int) ?? .null
                ])
            return item
        }
    }

    func recent(limit: Int, filter: HistoryFilter = .all) throws -> [ClipboardItem] {
        try locked {
            let clause = filterClause(filter)
            return try fetchMany("SELECT * FROM clipboard_items \(clause.sql) ORDER BY is_pinned DESC, coalesce(pinned_order, 999999), last_copied_at DESC LIMIT ?", binds: clause.binds + [.int(limit)])
        }
    }

    func search(_ query: String, filter: HistoryFilter = .all, limit: Int = 100) throws -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try recent(limit: limit, filter: filter) }
        return try locked {
            let terms = trimmed.split(whereSeparator: { $0.isWhitespace }).map { "\(escapeFTS(String($0)))*" }.joined(separator: " ")
            let clause = filterClause(filter, prefix: "i.")
            let whereJoin = clause.sql.isEmpty ? "WHERE" : "\(clause.sql) AND"
            let sql = "SELECT i.* FROM clipboard_items i JOIN clipboard_fts f ON f.id=i.id "
                + "\(whereJoin) clipboard_fts MATCH ? "
                + "ORDER BY bm25(clipboard_fts), i.is_pinned DESC, i.last_copied_at DESC LIMIT ?"
            return try fetchMany(sql, binds: clause.binds + [.text(terms), .int(limit)])
        }
    }

    func item(id: UUID) throws -> ClipboardItem? {
        try locked { try fetchOne("SELECT * FROM clipboard_items WHERE id=?", binds: [.text(id.uuidString)]) }
    }

    func setPinned(_ pinned: Bool, id: UUID) throws {
        try locked {
            if pinned {
                guard let item = try fetchOne("SELECT * FROM clipboard_items WHERE id=?", binds: [.text(id.uuidString)]),
                      item.contentType.canBePinned else { return }
                if item.isPinned { return }
                let pinnedCount = try fetchInteger("SELECT count(*) FROM clipboard_items WHERE is_pinned=1")
                guard pinnedCount < AppSettings.maxPinnedItems else {
                    throw NabiraError.pinLimitReached(AppSettings.maxPinnedItems)
                }
            }
            try run(
                "UPDATE clipboard_items SET is_pinned=?, pinned_order=CASE WHEN ?=1 THEN coalesce((SELECT max(pinned_order)+1 FROM clipboard_items),0) ELSE NULL END WHERE id=? AND (?=0 OR content_type NOT IN ('image','files'))",
                binds: [.int(pinned ? 1 : 0), .int(pinned ? 1 : 0), .text(id.uuidString), .int(pinned ? 1 : 0)]
            )
        }
    }

    func delete(id: UUID) throws {
        try locked { try run("DELETE FROM clipboard_items WHERE id=?", binds: [.text(id.uuidString)]) }
    }

    func clear(since: Date?, includePinned: Bool = false) throws {
        try locked {
            var conditions = includePinned ? [] : ["is_pinned=0"]
            var binds: [Bind] = []
            if let since { conditions.append("last_copied_at>=?"); binds.append(.double(since.timeIntervalSince1970)) }
            try run("DELETE FROM clipboard_items" + (conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")), binds: binds)
        }
    }

    func prune(maxItems: Int, maxBytes: Int, olderThan: Date) throws {
        try locked {
            try run("DELETE FROM clipboard_items WHERE is_pinned=0 AND last_copied_at<?", binds: [.double(olderThan.timeIntervalSince1970)])
            try run("DELETE FROM clipboard_items WHERE is_pinned=0 AND id NOT IN (SELECT id FROM clipboard_items WHERE is_pinned=0 ORDER BY last_copied_at DESC LIMIT ?)", binds: [.int(maxItems)])
            try run("""
                DELETE FROM clipboard_items WHERE id IN (
                    SELECT id FROM (
                        SELECT id, SUM(byte_count) OVER (ORDER BY last_copied_at DESC, id DESC) AS running_bytes
                        FROM clipboard_items WHERE is_pinned=0
                    ) WHERE running_bytes>?
                )
                """, binds: [.int(maxBytes)])
        }
    }

    private func filterClause(_ filter: HistoryFilter, prefix: String = "") -> (sql: String, binds: [Bind]) {
        let p = prefix
        switch filter {
        case .all: return ("", [])
        case .favorites: return ("WHERE \(p)is_pinned=1", [])
        case .text: return ("WHERE \(p)content_type IN ('text','richText','html','color')", [])
        case .links: return ("WHERE \(p)content_type='url'", [])
        case .images: return ("WHERE \(p)content_type='image'", [])
        case .files: return ("WHERE \(p)content_type='files'", [])
        }
    }

    private func escapeFTS(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    private enum Bind { case text(String), optionalText(String?), blob(Data), double(Double), int(Int), null }

    private func run(_ sql: String, binds: [Bind] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw dbError() }
        defer { sqlite3_finalize(statement) }
        bind(binds, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw dbError() }
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(error)
            throw NabiraError.database(message)
        }
    }

    private func fetchOne(_ sql: String, binds: [Bind]) throws -> ClipboardItem? { try fetchMany(sql, binds: binds).first }

    private func fetchInteger(_ sql: String, binds: [Bind] = []) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw dbError() }
        defer { sqlite3_finalize(statement) }
        bind(binds, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw dbError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func fetchMany(_ sql: String, binds: [Bind]) throws -> [ClipboardItem] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw dbError() }
        defer { sqlite3_finalize(statement) }
        bind(binds, to: statement)
        var result: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(try decodeRow(statement)) }
        return result
    }

    private func decodeRow(_ s: OpaquePointer?) throws -> ClipboardItem {
        func text(_ index: Int32) -> String { sqlite3_column_text(s, index).map { String(cString: $0) } ?? "" }
        let blobSize = Int(sqlite3_column_bytes(s, 4))
        let data = sqlite3_column_blob(s, 4).map { Data(bytes: $0, count: blobSize) } ?? Data()
        return ClipboardItem(
            id: UUID(uuidString: text(0))!, contentType: ClipboardContentType(rawValue: text(1)) ?? .unknown,
            searchableText: text(2), title: text(3), representations: try decoder.decode([PasteboardRepresentation].self, from: data),
            sourceBundleID: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : text(5),
            sourceAppName: sqlite3_column_type(s, 6) == SQLITE_NULL ? nil : text(6),
            firstCopiedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)),
            lastCopiedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 8)), copyCount: Int(sqlite3_column_int64(s, 9)),
            byteCount: Int(sqlite3_column_int64(s, 10)), isPinned: sqlite3_column_int(s, 11) != 0,
            contentHash: text(12), pinnedOrder: sqlite3_column_type(s, 13) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, 13)))
    }

    private func bind(_ values: [Bind], to statement: OpaquePointer?) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let i = Int32(offset + 1)
            switch value {
            case .text(let value): sqlite3_bind_text(statement, i, value, -1, transient)
            case .optionalText(let value):
                if let value { _ = sqlite3_bind_text(statement, i, value, -1, transient) } else { _ = sqlite3_bind_null(statement, i) }
            case .blob(let data): _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, i, $0.baseAddress, Int32(data.count), transient) }
            case .double(let value): sqlite3_bind_double(statement, i, value)
            case .int(let value): sqlite3_bind_int64(statement, i, sqlite3_int64(value))
            case .null: sqlite3_bind_null(statement, i)
            }
        }
    }

    private func dbError() -> NabiraError { .database(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error") }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        return try operation()
    }
}
