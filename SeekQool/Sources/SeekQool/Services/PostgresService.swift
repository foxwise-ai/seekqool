import Foundation
import PostgresNIO
import NIOCore
import NIOPosix
import Logging

actor PostgresService {
    private var connections: [UUID: PostgresConnection] = [:]
    private var connectionConfigs: [UUID: ConnectionConfig] = [:]
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger

    init() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 4)
        var logger = Logger(label: "seekqool.postgres")
        logger.logLevel = .warning
        self.logger = logger
    }

    private func logSQL(_ sql: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] SQL: \(sql)")
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] \(message)")
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    func connect(config: ConnectionConfig) async throws -> Bool {
        // Store config for reconnection
        connectionConfigs[config.id] = config

        if connections[config.id] != nil {
            // Check if existing connection is healthy
            if await isConnectionHealthy(configId: config.id) {
                return true
            }
            // Connection is stale, remove it
            connections.removeValue(forKey: config.id)
        }

        return try await establishConnection(config: config)
    }

    private func establishConnection(config: ConnectionConfig) async throws -> Bool {
        log("Connecting to \(config.host):\(config.port)/\(config.database)...")

        let pgConfig = PostgresConnection.Configuration(
            host: config.host,
            port: config.port,
            username: config.username,
            password: config.password,
            database: config.database,
            tls: .disable
        )

        // Use a timeout for connection attempts
        let connection = try await withThrowingTaskGroup(of: PostgresConnection.self) { group in
            group.addTask {
                try await PostgresConnection.connect(
                    on: self.eventLoopGroup.next(),
                    configuration: pgConfig,
                    id: 1,
                    logger: self.logger
                )
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout
                throw PostgresError.connectionFailed("Connection timed out after 10 seconds")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        connections[config.id] = connection
        log("Connected successfully to \(config.database)")
        return true
    }

    func disconnect(configId: UUID) async {
        guard let connection = connections[configId] else { return }
        try? await connection.close()
        connections.removeValue(forKey: configId)
        connectionConfigs.removeValue(forKey: configId)
        log("Disconnected")
    }

    func isConnected(configId: UUID) -> Bool {
        connections[configId] != nil
    }

    func isConnectionHealthy(configId: UUID) async -> Bool {
        guard let connection = connections[configId] else { return false }

        do {
            // Health check with 5 second timeout
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    let query = PostgresQuery(unsafeSQL: "SELECT 1")
                    let rows = try await connection.query(query, logger: self.logger)
                    for try await _ in rows {
                        return true
                    }
                    return true
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
                    throw PostgresError.connectionFailed("Health check timed out")
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            log("Connection health check failed: \(error.localizedDescription)")
            return false
        }
    }

    func reconnectIfNeeded(configId: UUID) async throws -> Bool {
        // Check if we have a stored config
        guard let config = connectionConfigs[configId] else {
            throw PostgresError.notConnected
        }

        // Check if connection is healthy
        if await isConnectionHealthy(configId: configId) {
            return true
        }

        // Connection is dead, try to reconnect
        log("Connection lost, attempting to reconnect...")
        connections.removeValue(forKey: configId)

        do {
            return try await establishConnection(config: config)
        } catch {
            log("Reconnection failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func ensureConnection(configId: UUID) async throws -> PostgresConnection {
        // Try to get existing connection
        if let connection = connections[configId] {
            return connection
        }

        // Try to reconnect
        _ = try await reconnectIfNeeded(configId: configId)

        guard let connection = connections[configId] else {
            throw PostgresError.notConnected
        }
        return connection
    }

    private func executeWithReconnect<T: Sendable>(configId: UUID, operation: @Sendable @escaping (PostgresConnection) async throws -> T) async throws -> T {
        // First attempt with timeout
        do {
            let connection = try await ensureConnection(configId: configId)
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation(connection)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second query timeout
                    throw PostgresError.queryFailed("Query timed out after 30 seconds")
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            // Check if this looks like a connection error
            let errorString = String(describing: error).lowercased()
            let isConnectionError = errorString.contains("connection") ||
                                   errorString.contains("closed") ||
                                   errorString.contains("reset") ||
                                   errorString.contains("broken") ||
                                   errorString.contains("eof") ||
                                   errorString.contains("timed out")

            if isConnectionError {
                log("Query failed with connection error, attempting reconnect...")
                connections.removeValue(forKey: configId)

                // Try to reconnect and retry (with timeout)
                _ = try await reconnectIfNeeded(configId: configId)
                let connection = try await ensureConnection(configId: configId)

                return try await withThrowingTaskGroup(of: T.self) { group in
                    group.addTask {
                        try await operation(connection)
                    }

                    group.addTask {
                        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second query timeout
                        throw PostgresError.queryFailed("Query timed out after 30 seconds")
                    }

                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
            } else {
                throw error
            }
        }
    }

    func listDatabases(configId: UUID) async throws -> [DatabaseInfo] {
        let sql = """
            SELECT datname FROM pg_database
            WHERE datistemplate = false
            ORDER BY datname
            """
        logSQL(sql)

        return try await executeWithReconnect(configId: configId) { connection in
            let query = PostgresQuery(unsafeSQL: sql)
            let rows = try await connection.query(query, logger: self.logger)
            var databases: [DatabaseInfo] = []

            for try await row in rows {
                if let name = try? row.decode(String.self, context: .default) {
                    databases.append(DatabaseInfo(name: name))
                }
            }

            return databases
        }
    }

    func listSchemas(configId: UUID) async throws -> [SchemaInfo] {
        let sql = """
            SELECT schema_name FROM information_schema.schemata
            WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
            ORDER BY schema_name
            """
        logSQL(sql)

        return try await executeWithReconnect(configId: configId) { connection in
            let query = PostgresQuery(unsafeSQL: sql)
            let rows = try await connection.query(query, logger: self.logger)
            var schemas: [SchemaInfo] = []

            for try await row in rows {
                if let name = try? row.decode(String.self, context: .default) {
                    schemas.append(SchemaInfo(name: name))
                }
            }

            return schemas
        }
    }

    func listTables(configId: UUID, schema: String = "public") async throws -> [TableInfo] {
        let sql = """
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema = '\(schema)'
            ORDER BY table_type, table_name
            """
        logSQL(sql)

        return try await executeWithReconnect(configId: configId) { connection in
            let query = PostgresQuery(unsafeSQL: sql)
            let rows = try await connection.query(query, logger: self.logger)
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
    }

    func getColumns(configId: UUID, schema: String, table: String) async throws -> [ColumnInfo] {
        let sql = """
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
        logSQL(sql)

        return try await executeWithReconnect(configId: configId) { connection in
            let query = PostgresQuery(unsafeSQL: sql)
            let rows = try await connection.query(query, logger: self.logger)
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
    }

    func getTableRowCount(configId: UUID, schema: String, table: String) async throws -> Int {
        let sql = "SELECT COUNT(*) FROM \"\(schema)\".\"\(table)\""
        logSQL(sql)

        return try await executeWithReconnect(configId: configId) { connection in
            let query = PostgresQuery(unsafeSQL: sql)
            let rows = try await connection.query(query, logger: self.logger)

            for try await row in rows {
                if let count = try? row.decode(Int.self, context: .default) {
                    return count
                }
            }

            return 0
        }
    }

    func fetchTableData(
        configId: UUID,
        schema: String,
        table: String,
        columns: [ColumnInfo],
        page: Int,
        pageSize: Int,
        sortColumn: String? = nil,
        sortAscending: Bool = true
    ) async throws -> [[CellValue]] {
        let offset = (page - 1) * pageSize
        let columnList = columns.map { "\"\($0.name)\"" }.joined(separator: ", ")

        var sqlBuilder = """
            SELECT \(columnList)
            FROM "\(schema)"."\(table)"
            """

        if let sortCol = sortColumn {
            let direction = sortAscending ? "ASC" : "DESC"
            sqlBuilder += "\nORDER BY \"\(sortCol)\" \(direction) NULLS LAST"
        }

        sqlBuilder += "\nLIMIT \(pageSize) OFFSET \(offset)"
        let sql = sqlBuilder
        logSQL(sql)

        return try await executeWithReconnect(configId: configId) { connection in
            let query = PostgresQuery(unsafeSQL: sql)
            let rows = try await connection.query(query, logger: self.logger)
            var result: [[CellValue]] = []

            for try await row in rows {
                var rowValues: [CellValue] = []
                let randomAccessRow = row.makeRandomAccess()

                for (index, column) in columns.enumerated() {
                    if index < randomAccessRow.count {
                        let cellValue = try self.decodeCell(from: randomAccessRow, at: index, dataType: column.dataType)
                        rowValues.append(cellValue)
                    } else {
                        rowValues.append(.null)
                    }
                }

                result.append(rowValues)
            }

            return result
        }
    }

    func executeQuery(configId: UUID, sql: String) async throws -> (columns: [ColumnInfo], rows: [[CellValue]]) {
        logSQL(sql)

        return try await executeWithReconnect(configId: configId) { connection in
            let query = PostgresQuery(unsafeSQL: sql)
            let rowSequence = try await connection.query(query, logger: self.logger)

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
                    let cellValue = try self.decodeCell(from: randomAccessRow, at: index, dataType: "text")
                    rowValues.append(cellValue)
                }

                resultRows.append(rowValues)
            }

            return (columns, resultRows)
        }
    }

    func executeUpdate(configId: UUID, sql: String) async throws -> Int {
        logSQL(sql)

        return try await executeWithReconnect(configId: configId) { connection in
            let query = PostgresQuery(unsafeSQL: sql)
            let _ = try await connection.query(query, logger: self.logger)
            return 1
        }
    }

    private nonisolated func decodeCell(from row: PostgresRandomAccessRow, at index: Int, dataType: String) throws -> CellValue {
        let cell = row[index]

        guard var bytes = cell.bytes else {
            return .null
        }

        let lowerType = dataType.lowercased()

        // Handle bigint (int8) - PostgreSQL sends as 8-byte binary
        if lowerType == "bigint" || lowerType == "int8" || lowerType == "bigserial" {
            if bytes.readableBytes == 8 {
                if let value = bytes.readInteger(as: Int64.self) {
                    return .int(Int(value))
                }
            }
            // Fallback to string parsing
            let stringValue = String(decoding: bytes.readableBytesView, as: UTF8.self)
            if let intVal = Int(stringValue) {
                return .int(intVal)
            }
            return .string(stringValue)
        }

        // Handle integer (int4) - PostgreSQL sends as 4-byte binary
        if lowerType == "integer" || lowerType == "int" || lowerType == "int4" || lowerType == "serial" {
            if bytes.readableBytes == 4 {
                if let value = bytes.readInteger(as: Int32.self) {
                    return .int(Int(value))
                }
            }
            // Fallback to string parsing
            let stringValue = String(decoding: bytes.readableBytesView, as: UTF8.self)
            if let intVal = Int(stringValue) {
                return .int(intVal)
            }
            return .string(stringValue)
        }

        // Handle smallint (int2) - PostgreSQL sends as 2-byte binary
        if lowerType == "smallint" || lowerType == "int2" || lowerType == "smallserial" {
            if bytes.readableBytes == 2 {
                if let value = bytes.readInteger(as: Int16.self) {
                    return .int(Int(value))
                }
            }
            // Fallback to string parsing
            let stringValue = String(decoding: bytes.readableBytesView, as: UTF8.self)
            if let intVal = Int(stringValue) {
                return .int(intVal)
            }
            return .string(stringValue)
        }

        // Handle timestamps - PostgreSQL sends as binary (microseconds since 2000-01-01)
        if lowerType.contains("timestamp") || lowerType == "timestamptz" {
            if bytes.readableBytes == 8 {
                let microseconds = bytes.readInteger(as: Int64.self) ?? 0
                // PostgreSQL epoch is 2000-01-01, Unix epoch is 1970-01-01
                // Difference is 946684800 seconds
                let unixTimestamp = Double(microseconds) / 1_000_000.0 + 946684800.0
                let date = Date(timeIntervalSince1970: unixTimestamp)
                return .date(date)
            }
            // Fallback to string if not 8 bytes
            let stringValue = String(decoding: bytes.readableBytesView, as: UTF8.self)
            return .string(stringValue)
        }

        // Handle date type
        if lowerType == "date" {
            if bytes.readableBytes == 4 {
                let days = bytes.readInteger(as: Int32.self) ?? 0
                // Days since 2000-01-01
                let unixTimestamp = Double(days) * 86400.0 + 946684800.0
                let date = Date(timeIntervalSince1970: unixTimestamp)
                return .date(date)
            }
        }

        // Handle time type
        if lowerType.contains("time") && !lowerType.contains("timestamp") {
            if bytes.readableBytes == 8 {
                let microseconds = bytes.readInteger(as: Int64.self) ?? 0
                let seconds = Double(microseconds) / 1_000_000.0
                let hours = Int(seconds / 3600)
                let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
                let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
                return .string(String(format: "%02d:%02d:%02d", hours, minutes, secs))
            }
        }

        // Handle boolean - PostgreSQL sends as 1-byte binary
        if lowerType == "boolean" || lowerType == "bool" {
            if bytes.readableBytes == 1 {
                if let value = bytes.readInteger(as: UInt8.self) {
                    return .bool(value != 0)
                }
            }
            let stringValue = String(decoding: bytes.readableBytesView, as: UTF8.self)
            return .bool(stringValue == "t" || stringValue == "true" || stringValue == "1")
        }

        // Handle float4 (real) - 4-byte binary
        if lowerType == "real" || lowerType == "float4" {
            if bytes.readableBytes == 4 {
                if let bits = bytes.readInteger(as: UInt32.self) {
                    let value = Float(bitPattern: bits)
                    return .double(Double(value))
                }
            }
        }

        // Handle float8 (double precision) - 8-byte binary
        if lowerType == "double precision" || lowerType == "float8" {
            if bytes.readableBytes == 8 {
                if let bits = bytes.readInteger(as: UInt64.self) {
                    let value = Double(bitPattern: bits)
                    return .double(value)
                }
            }
        }

        let stringValue = String(decoding: bytes.readableBytesView, as: UTF8.self)

        // Handle numeric/decimal as string (variable precision)
        if lowerType == "numeric" || lowerType == "decimal" {
            if let doubleVal = Double(stringValue) {
                return .double(doubleVal)
            }
            return .string(stringValue)
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
