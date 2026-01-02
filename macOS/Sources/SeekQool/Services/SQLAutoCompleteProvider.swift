import Foundation

struct CompletionItem: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let detail: String
    let type: CompletionType

    enum CompletionType {
        case table
        case column
        case keyword
    }

    var icon: String {
        switch type {
        case .table: return "tablecells"
        case .column: return "line.3.horizontal"
        case .keyword: return "textformat"
        }
    }
}

@MainActor
class SQLAutoCompleteProvider: ObservableObject {
    private let postgresService: PostgresService
    private let connectionId: UUID

    // Cache
    private var tableCache: [String: [String]] = [:] // schema -> [table names]
    private var columnCache: [String: [ColumnInfo]] = [:] // "schema.table" -> columns

    init(postgresService: PostgresService, connectionId: UUID) {
        self.postgresService = postgresService
        self.connectionId = connectionId
    }

    func loadTables() async {
        do {
            let schemas = try await postgresService.listSchemas(configId: connectionId)
            for schema in schemas {
                let tables = try await postgresService.listTables(configId: connectionId, schema: schema.name)
                tableCache[schema.name] = tables.map { $0.name }
            }
        } catch {
            print("Failed to load tables for autocomplete: \(error)")
        }
    }

    func getCompletions(for text: String, cursorPosition: Int) async -> [CompletionItem] {
        let prefix = String(text.prefix(cursorPosition))
        let fullQuery = text.lowercased()

        // Find the word being typed by scanning backwards
        var wordStart = prefix.endIndex
        for i in prefix.indices.reversed() {
            let char = prefix[i]
            if char.isLetter || char.isNumber || char == "_" || char == "." {
                wordStart = i
            } else {
                break
            }
        }

        guard wordStart < prefix.endIndex else {
            return []
        }

        let currentWord = String(prefix[wordStart...]).lowercased()

        // Check if we're completing after a dot (table.column or alias.column)
        if currentWord.contains(".") {
            let parts = currentWord.split(separator: ".")
            if parts.count >= 1 {
                let tableOrAlias = String(parts[0])
                let columnPrefix = parts.count > 1 ? String(parts[1]) : ""

                // Try to resolve alias to actual table name
                let tableName = resolveAlias(tableOrAlias, in: fullQuery) ?? tableOrAlias
                return await getColumnCompletions(table: tableName, prefix: columnPrefix)
            }
        }

        // Otherwise, suggest tables and keywords
        return getTableAndKeywordCompletions(prefix: currentWord)
    }

    /// Resolves a table alias to the actual table name by parsing the query
    private func resolveAlias(_ alias: String, in query: String) -> String? {
        // Patterns to match: "table_name alias", "table_name AS alias"
        // Look for patterns like "from users u" or "join devices d" or "from users as u"

        let patterns = [
            // "FROM table alias" or "JOIN table alias"
            "(?:from|join)\\s+(\\w+)\\s+(?:as\\s+)?(\(alias))(?:\\s|$|,)",
            // Also check for schema.table alias
            "(?:from|join)\\s+(\\w+\\.\\w+)\\s+(?:as\\s+)?(\(alias))(?:\\s|$|,)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(query.startIndex..., in: query)
                if let match = regex.firstMatch(in: query, options: [], range: range) {
                    if let tableRange = Range(match.range(at: 1), in: query) {
                        let tableName = String(query[tableRange])
                        // If it's schema.table, just return the table part
                        if tableName.contains(".") {
                            return tableName.split(separator: ".").last.map(String.init)
                        }
                        return tableName
                    }
                }
            }
        }

        return nil
    }

    private func getTableAndKeywordCompletions(prefix: String) -> [CompletionItem] {
        var completions: [CompletionItem] = []

        // Add matching tables
        for (schema, tables) in tableCache {
            for table in tables {
                if prefix.isEmpty || table.lowercased().hasPrefix(prefix) {
                    completions.append(CompletionItem(
                        text: table,
                        detail: schema,
                        type: .table
                    ))
                }
            }
        }

        // Add matching SQL keywords (only if we have a prefix)
        if !prefix.isEmpty {
            let keywords = ["SELECT", "FROM", "WHERE", "AND", "OR", "JOIN", "LEFT", "RIGHT",
                          "INNER", "OUTER", "ON", "GROUP BY", "ORDER BY", "LIMIT", "OFFSET",
                          "INSERT", "UPDATE", "DELETE", "SET", "VALUES", "INTO",
                          "DISTINCT", "AS", "NULL", "NOT", "IN", "LIKE", "BETWEEN",
                          "COUNT", "SUM", "AVG", "MAX", "MIN", "HAVING"]

            for keyword in keywords {
                if keyword.lowercased().hasPrefix(prefix) {
                    completions.append(CompletionItem(
                        text: keyword,
                        detail: "keyword",
                        type: .keyword
                    ))
                }
            }
        }

        // Sort: tables first, then keywords, alphabetically
        return completions.sorted {
            if $0.type == $1.type {
                return $0.text < $1.text
            }
            return $0.type == .table
        }
    }

    private func getColumnCompletions(table: String, prefix: String) async -> [CompletionItem] {
        // Find the table in our cache
        var foundSchema: String?
        var foundTable: String?

        for (schema, tables) in tableCache {
            if let match = tables.first(where: { $0.lowercased() == table }) {
                foundSchema = schema
                foundTable = match
                break
            }
        }

        guard let schema = foundSchema, let tableName = foundTable else {
            return []
        }

        // Get columns (from cache or fetch)
        let cacheKey = "\(schema).\(tableName)"
        let columns: [ColumnInfo]

        if let cached = columnCache[cacheKey] {
            columns = cached
        } else {
            do {
                let fetched = try await postgresService.getColumns(configId: connectionId, schema: schema, table: tableName)
                columnCache[cacheKey] = fetched
                columns = fetched
            } catch {
                print("Failed to fetch columns: \(error)")
                return []
            }
        }

        // Filter by prefix
        return columns
            .filter { prefix.isEmpty || $0.name.lowercased().hasPrefix(prefix) }
            .map { column in
                CompletionItem(
                    text: column.name,
                    detail: column.dataType,
                    type: .column
                )
            }
    }
}
