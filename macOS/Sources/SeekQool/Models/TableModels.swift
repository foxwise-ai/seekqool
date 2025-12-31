import Foundation

struct DatabaseInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

struct SchemaInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

struct TableInfo: Identifiable, Hashable {
    let id = UUID()
    let schema: String
    let name: String
    let type: TableType

    var fullName: String {
        "\(schema).\(name)"
    }

    enum TableType: String {
        case table = "BASE TABLE"
        case view = "VIEW"
    }
}

struct ColumnInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let dataType: String
    let isNullable: Bool
    let isPrimaryKey: Bool
    let ordinalPosition: Int
    var isHidden: Bool = false
}

struct TableData {
    var columns: [ColumnInfo]
    var rows: [[CellValue]]
    var primaryKeyColumns: [String]
    var totalRowCount: Int
    var currentPage: Int
    var pageSize: Int

    var totalPages: Int {
        max(1, (totalRowCount + pageSize - 1) / pageSize)
    }

    var visibleColumns: [ColumnInfo] {
        columns.filter { !$0.isHidden }
    }

    var visibleColumnIndices: [Int] {
        columns.enumerated().compactMap { $0.element.isHidden ? nil : $0.offset }
    }

    func visibleCells(for row: [CellValue]) -> [CellValue] {
        visibleColumnIndices.map { row[$0] }
    }

    init(
        columns: [ColumnInfo] = [],
        rows: [[CellValue]] = [],
        primaryKeyColumns: [String] = [],
        totalRowCount: Int = 0,
        currentPage: Int = 1,
        pageSize: Int = 100
    ) {
        self.columns = columns
        self.rows = rows
        self.primaryKeyColumns = primaryKeyColumns
        self.totalRowCount = totalRowCount
        self.currentPage = currentPage
        self.pageSize = pageSize
    }
}

enum CellValue: Hashable, CustomStringConvertible {
    case null
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case uuid(UUID)
    case json(String)

    var description: String {
        switch self {
        case .null:
            return "NULL"
        case .string(let s):
            return s
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .bool(let b):
            return b ? "true" : "false"
        case .date(let d):
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: d)
        case .data(let data):
            return "\\x" + data.map { String(format: "%02x", $0) }.joined()
        case .uuid(let u):
            return u.uuidString
        case .json(let j):
            return j
        }
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    func sqlLiteral() -> String {
        switch self {
        case .null:
            return "NULL"
        case .string(let s):
            return "'\(s.replacingOccurrences(of: "'", with: "''"))'"
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .bool(let b):
            return b ? "TRUE" : "FALSE"
        case .date(let d):
            let formatter = ISO8601DateFormatter()
            return "'\(formatter.string(from: d))'"
        case .data(let data):
            return "'\\x" + data.map { String(format: "%02x", $0) }.joined() + "'"
        case .uuid(let u):
            return "'\(u.uuidString)'"
        case .json(let j):
            return "'\(j.replacingOccurrences(of: "'", with: "''"))'::jsonb"
        }
    }

    static func from(string: String, forType dataType: String, wasNull: Bool = false) -> CellValue {
        if wasNull || string.uppercased() == "NULL" {
            return .null
        }

        let lowerType = dataType.lowercased()

        if lowerType.contains("int") || lowerType == "serial" || lowerType == "bigserial" || lowerType == "smallserial" {
            if let i = Int(string) {
                return .int(i)
            }
        }

        if lowerType.contains("float") || lowerType.contains("double") || lowerType == "real" || lowerType == "numeric" || lowerType == "decimal" {
            if let d = Double(string) {
                return .double(d)
            }
        }

        if lowerType == "boolean" || lowerType == "bool" {
            let lower = string.lowercased()
            return .bool(lower == "true" || lower == "t" || lower == "1" || lower == "yes")
        }

        if lowerType == "uuid" {
            if let u = UUID(uuidString: string) {
                return .uuid(u)
            }
        }

        if lowerType.contains("json") {
            return .json(string)
        }

        return .string(string)
    }
}
