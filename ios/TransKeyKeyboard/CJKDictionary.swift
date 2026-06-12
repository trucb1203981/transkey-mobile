import Foundation
import SQLite3

/// Read-only SQLite access shared by the pinyin->hanzi and kana->kanji
/// converters. The bundled .db is opened in place (no copy step - unlike
/// Android assets, bundle resources are plain files), and every lookup is a
/// short indexed query, so memory stays within the keyboard-extension cap.
final class CJKDictionary {

    private var db: OpaquePointer?
    var isReady: Bool { db != nil }

    init(resource: String) {
        guard let path = Bundle.main.path(forResource: resource, ofType: "db") else { return }
        var handle: OpaquePointer?
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            db = handle
        } else {
            sqlite3_close(handle)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// Run [sql] with TEXT bindings, returning the first column as strings.
    func strings(_ sql: String, _ args: [String]) -> [String] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, transient)
        }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                out.append(String(cString: c))
            }
        }
        return out
    }
}
