import Foundation
import PostgresNIO
import NIOCore
import NIOPosix
import Logging

actor PostgresService {
    private var connections: [UUID: PostgresConnection] = [:]
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger

    init() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 4)
        var logger = Logger(label: "seekqool.postgres")
        logger.logLevel = .warning
        self.logger = logger
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    func connect(config: ConnectionConfig) async throws -> Bool {
        if connections[config.id] != nil {
            return true
        }

        let pgConfig = PostgresConnection.Configuration(
            host: config.host,
            port: config.port,
            username: config.username,
            password: config.password,
            database: config.database,
            tls: .disable
        )

        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: pgConfig,
            id: 1,
            logger: logger
        )

        connections[config.id] = connection
        return true
    }

    func disconnect(configId: UUID) async {
        guard let connection = connections[configId] else { return }
        try? await connection.close()
        connections.removeValue(forKey: configId)
    }

    func isConnected(configId: UUID) -> Bool {
        connections[configId] != nil
    }

    func listDatabases(configId: UUID) async throws -> [DatabaseInfo] {
        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }

        let query = PostgresQuery(
            unsafeSQL: """
            SELECT datname FROM pg_database
            WHERE datistemplate = false
            ORDER BY datname
            """
        )

        let rows = try await connection.query(query, logger: logger)
        var databases: [DatabaseInfo] = []

        for try await row in rows {
            if let name = try? row.decode(String.self, context: .default) {
                databases.append(DatabaseInfo(name: name))
            }
        }

        return databases
    }

    func listSchemas(configId: UUID) async throws -> [SchemaInfo] {
        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }

        let query = PostgresQuery(
            unsafeSQL: """
            SELECT schema_name FROM information_schema.schemata
            WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
            ORDER BY schema_name
            """
        )

        let rows = try await connection.query(query, logger: logger)
        var schemas: [SchemaInfo] = []

        for try await row in rows {
            if let name = try? row.decode(String.self, context: .default) {
                schemas.append(SchemaInfo(name: name))
            }
        }

        return schemas
    }

    func listTables(configId: UUID, schema: String = "public") async throws -> [TableInfo] {
        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }

        let query = PostgresQuery(
            unsafeSQL: """
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema = '\(schema)'
            ORDER BY table_type, table_name
            """
        )

        let rows = try await connection.query(query, logger: logger)
        var tables: [TableInfo] = []

        for try await row in rows {
            let columns = row.makeRandomAccess()
            if columns.count >= 3 {
                let schemaName = try columns[0].decode(String.self, context: .default)
                let tableName = try columns[1].decode(String.self, context: .default)
                let tableTypeStr = try columns[2].decode(String.self, context: .default)
                let tableType: TableInfo.TableType = tableTypeStr == "VIEW" ? .view : .table
                tables.append(TableInfo(schema: schemaName, name: tableName, type: tableType))
            }
        }

        return tables
    }

    func getColumns(configId: UUID, schema: String, table: String) async throws -> [ColumnInfo] {
        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }

        let query = PostgresQuery(
            unsafeSQL: """
            SELECT
                c.column_name,
                c.data_type,
                c.is_nullable,
                c.ordinal_position,
                CASE WHEN pk.column_name IS NOT NULL THEN true ELSE false END as is_primary_key
            FROM information_schema.columns c
            LEFT JOIN (
                SELECT ku.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage ku
                    ON tc.constraint_name = ku.constraint_name
                    AND tc.table_schema = ku.table_schema
                WHERE tc.constraint_type = 'PRIMARY KEY'
                    AND tc.table_schema = '\(schema)'
                    AND tc.table_name = '\(table)'
            ) pk ON c.column_name = pk.column_name
            WHERE c.table_schema = '\(schema)' AND c.table_name = '\(table)'
            ORDER BY c.ordinal_position
            """
        )

        let rows = try await connection.query(query, logger: logger)
        var columns: [ColumnInfo] = []

        for try await row in rows {
            let cols = row.makeRandomAccess()
            if cols.count >= 5 {
                let name = try cols[0].decode(String.self, context: .default)
                let dataType = try cols[1].decode(String.self, context: .default)
                let isNullableStr = try cols[2].decode(String.self, context: .default)
                let ordinal = try cols[3].decode(Int.self, context: .default)
                let isPK = try cols[4].decode(Bool.self, context: .default)

                columns.append(ColumnInfo(
                    name: name,
                    dataType: dataType,
                    isNullable: isNullableStr == "YES",
                    isPrimaryKey: isPK,
                    ordinalPosition: ordinal
                ))
            }
        }

        return columns
    }

    func getTableRowCount(configId: UUID, schema: String, table: String) async throws -> Int {
        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }

        let query = PostgresQuery(
            unsafeSQL: "SELECT COUNT(*) FROM \"\(schema)\".\"\(table)\""
        )

        let rows = try await connection.query(query, logger: logger)

        for try await row in rows {
            if let count = try? row.decode(Int.self, context: .default) {
                return count
            }
        }

        return 0
    }

    func fetchTableData(
        configId: UUID,
        schema: String,
        table: String,
        columns: [ColumnInfo],
        page: Int,
        pageSize: Int
    ) async throws -> [[CellValue]] {
        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }

        let offset = (page - 1) * pageSize
        let columnList = columns.map { "\"\($0.name)\"" }.joined(separator: ", ")

        let query = PostgresQuery(
            unsafeSQL: """
            SELECT \(columnList)
            FROM "\(schema)"."\(table)"
            LIMIT \(pageSize) OFFSET \(offset)
            """
        )

        let rows = try await connection.query(query, logger: logger)
        var result: [[CellValue]] = []

        for try await row in rows {
            var rowValues: [CellValue] = []
            let randomAccessRow = row.makeRandomAccess()

            for (index, column) in columns.enumerated() {
                if index < randomAccessRow.count {
                    let cellValue = try decodeCell(from: randomAccessRow, at: index, dataType: column.dataType)
                    rowValues.append(cellValue)
                } else {
                    rowValues.append(.null)
                }
            }

            result.append(rowValues)
        }

        return result
    }

    func executeQuery(configId: UUID, sql: String) async throws -> (columns: [ColumnInfo], rows: [[CellValue]]) {
        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }

        let query = PostgresQuery(unsafeSQL: sql)
        let rowSequence = try await connection.query(query, logger: logger)

        var columns: [ColumnInfo] = []
        var resultRows: [[CellValue]] = []
        var columnsExtracted = false

        for try await row in rowSequence {
            let randomAccessRow = row.makeRandomAccess()

            if !columnsExtracted {
                for index in 0..<randomAccessRow.count {
                    columns.append(ColumnInfo(
                        name: "column_\(index)",
                        dataType: "text",
                        isNullable: true,
                        isPrimaryKey: false,
                        ordinalPosition: index
                    ))
                }
                columnsExtracted = true
            }

            var rowValues: [CellValue] = []

            for index in 0..<randomAccessRow.count {
                let cellValue = try decodeCell(from: randomAccessRow, at: index, dataType: "text")
                rowValues.append(cellValue)
            }

            resultRows.append(rowValues)
        }

        return (columns, resultRows)
    }

    func executeUpdate(configId: UUID, sql: String) async throws -> Int {
        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }

        let query = PostgresQuery(unsafeSQL: sql)
        let _ = try await connection.query(query, logger: logger)

        return 1
    }

    private func decodeCell(from row: PostgresRandomAccessRow, at index: Int, dataType: String) throws -> CellValue {
        let cell = row[index]

        guard let bytes = cell.bytes else {
            return .null
        }

        let stringValue = String(decoding: bytes.readableBytesView, as: UTF8.self)

        let lowerType = dataType.lowercased()

        if lowerType.contains("int") || lowerType == "serial" || lowerType == "bigserial" {
            if let intVal = Int(stringValue) {
                return .int(intVal)
            }
        }

        if lowerType.contains("float") || lowerType.contains("double") || lowerType == "real" || lowerType == "numeric" || lowerType == "decimal" {
            if let doubleVal = Double(stringValue) {
                return .double(doubleVal)
            }
        }

        if lowerType == "boolean" || lowerType == "bool" {
            return .bool(stringValue == "t" || stringValue == "true" || stringValue == "1")
        }

        if lowerType == "uuid" {
            if let uuid = UUID(uuidString: stringValue) {
                return .uuid(uuid)
            }
        }

        if lowerType.contains("json") {
            return .json(stringValue)
        }

        return .string(stringValue)
    }
}

enum PostgresError: Error, LocalizedError {
    case notConnected
    case queryFailed(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to database"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}
