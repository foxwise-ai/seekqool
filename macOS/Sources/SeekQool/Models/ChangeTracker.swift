import Foundation

struct CellEdit: Identifiable, Hashable {
    let id = UUID()
    let rowIndex: Int
    let columnIndex: Int
    let columnName: String
    let originalValue: CellValue
    var newValue: CellValue
    let primaryKeyValues: [String: CellValue]
    let tableName: String
    let schemaName: String

    func generateSQL() -> String {
        guard !primaryKeyValues.isEmpty else {
            return "-- ERROR: No primary key found for table \(schemaName).\(tableName). Cannot generate UPDATE."
        }

        let whereClause = primaryKeyValues.map { key, value in
            "\"\(key)\" = \(value.sqlLiteral())"
        }.joined(separator: " AND ")

        let setClause = "\"\(columnName)\" = \(newValue.sqlLiteral())"

        return """
        UPDATE "\(schemaName)"."\(tableName)"
        SET \(setClause)
        WHERE \(whereClause);
        """
    }
}

struct RowDeletion: Identifiable, Hashable {
    let id = UUID()
    let rowIndex: Int
    let primaryKeyValues: [String: CellValue]
    let tableName: String
    let schemaName: String

    func generateSQL() -> String {
        guard !primaryKeyValues.isEmpty else {
            return "-- ERROR: No primary key found for table \(schemaName).\(tableName). Cannot generate DELETE."
        }

        let whereClause = primaryKeyValues.map { key, value in
            "\"\(key)\" = \(value.sqlLiteral())"
        }.joined(separator: " AND ")

        return """
        DELETE FROM "\(schemaName)"."\(tableName)"
        WHERE \(whereClause);
        """
    }
}

class PendingChanges: ObservableObject {
    @Published var edits: [CellEdit] = []
    @Published var deletions: [RowDeletion] = []

    var hasChanges: Bool {
        !edits.isEmpty || !deletions.isEmpty
    }

    var changeCount: Int {
        edits.count + deletions.count
    }

    func isRowDeleted(_ rowIndex: Int) -> Bool {
        deletions.contains { $0.rowIndex == rowIndex }
    }

    func addDeletion(_ deletion: RowDeletion) {
        // Don't add duplicate deletions
        guard !deletions.contains(where: { $0.rowIndex == deletion.rowIndex }) else { return }

        // Remove any edits for this row since it's being deleted
        edits.removeAll { $0.rowIndex == deletion.rowIndex }

        deletions.append(deletion)
    }

    func removeDeletion(at rowIndex: Int) {
        deletions.removeAll { $0.rowIndex == rowIndex }
    }

    func addEdit(_ edit: CellEdit) {
        if let existingIndex = edits.firstIndex(where: {
            $0.rowIndex == edit.rowIndex &&
            $0.columnIndex == edit.columnIndex &&
            $0.tableName == edit.tableName &&
            $0.schemaName == edit.schemaName
        }) {
            if edits[existingIndex].originalValue == edit.newValue {
                edits.remove(at: existingIndex)
            } else {
                edits[existingIndex].newValue = edit.newValue
            }
        } else {
            if edit.originalValue != edit.newValue {
                edits.append(edit)
            }
        }
    }

    func removeEdit(at index: Int) {
        guard index >= 0 && index < edits.count else { return }
        edits.remove(at: index)
    }

    func clear() {
        edits.removeAll()
        deletions.removeAll()
    }

    func generateAllSQL() -> String {
        if edits.isEmpty && deletions.isEmpty {
            return "-- No pending changes"
        }

        var sql = "-- SeekQool Generated SQL\n"
        sql += "-- \(changeCount) change(s) pending\n"
        sql += "-- Generated at: \(ISO8601DateFormatter().string(from: Date()))\n\n"

        var changeIndex = 1

        for edit in edits {
            sql += "-- Change \(changeIndex): Update \(edit.columnName) in row\n"
            sql += edit.generateSQL() + "\n\n"
            changeIndex += 1
        }

        for deletion in deletions {
            sql += "-- Change \(changeIndex): Delete row\n"
            sql += deletion.generateSQL() + "\n\n"
            changeIndex += 1
        }

        return sql
    }

    /// Returns individual SQL statements for execution
    func generateSQLStatements() -> [String] {
        var statements = edits.map { $0.generateSQL() }
        statements.append(contentsOf: deletions.map { $0.generateSQL() })
        return statements
    }

    func editForCell(rowIndex: Int, columnIndex: Int) -> CellEdit? {
        edits.first {
            $0.rowIndex == rowIndex && $0.columnIndex == columnIndex
        }
    }
}

struct QueryInfo {
    let originalQuery: String
    let tableName: String?
    let schemaName: String?
    let isEditable: Bool
    let nonEditableReason: String?

    static func analyze(query: String) -> QueryInfo {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard trimmed.hasPrefix("select") else {
            return QueryInfo(
                originalQuery: query,
                tableName: nil,
                schemaName: nil,
                isEditable: false,
                nonEditableReason: "Only SELECT queries can be edited"
            )
        }

        if trimmed.contains(" join ") {
            return QueryInfo(
                originalQuery: query,
                tableName: nil,
                schemaName: nil,
                isEditable: false,
                nonEditableReason: "Queries with JOINs cannot be edited (multiple tables)"
            )
        }

        if trimmed.contains(" union ") || trimmed.contains(" intersect ") || trimmed.contains(" except ") {
            return QueryInfo(
                originalQuery: query,
                tableName: nil,
                schemaName: nil,
                isEditable: false,
                nonEditableReason: "Set operations (UNION, INTERSECT, EXCEPT) cannot be edited"
            )
        }

        if trimmed.contains("group by") || trimmed.contains("having") {
            return QueryInfo(
                originalQuery: query,
                tableName: nil,
                schemaName: nil,
                isEditable: false,
                nonEditableReason: "Aggregated queries cannot be edited"
            )
        }

        let (schema, table) = extractTableName(from: query)

        guard let tableName = table else {
            return QueryInfo(
                originalQuery: query,
                tableName: nil,
                schemaName: nil,
                isEditable: false,
                nonEditableReason: "Could not determine table name from query"
            )
        }

        return QueryInfo(
            originalQuery: query,
            tableName: tableName,
            schemaName: schema ?? "public",
            isEditable: true,
            nonEditableReason: nil
        )
    }

    private static func extractTableName(from query: String) -> (schema: String?, table: String?) {
        let pattern = #"(?i)\bfrom\s+(?:"?(\w+)"?\.)?"?(\w+)"?"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: query,
                  range: NSRange(query.startIndex..., in: query)
              ) else {
            return (nil, nil)
        }

        var schema: String? = nil
        var table: String? = nil

        if let schemaRange = Range(match.range(at: 1), in: query) {
            schema = String(query[schemaRange])
        }

        if let tableRange = Range(match.range(at: 2), in: query) {
            table = String(query[tableRange])
        }

        return (schema, table)
    }
}
