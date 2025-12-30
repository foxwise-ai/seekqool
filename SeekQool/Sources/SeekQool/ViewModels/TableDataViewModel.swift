import Foundation
import SwiftUI

enum SortDirection {
    case ascending
    case descending

    var toggled: SortDirection {
        self == .ascending ? .descending : .ascending
    }
}

@MainActor
class TableDataViewModel: ObservableObject {
    @Published var tableData: TableData = TableData()
    @Published var pendingChanges: PendingChanges = PendingChanges()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showSQLPreview: Bool = false
    @Published var queryInfo: QueryInfo?

    // Sorting
    @Published var sortColumnIndex: Int? = nil
    @Published var sortDirection: SortDirection = .ascending

    let connectionConfig: ConnectionConfig
    let tableInfo: TableInfo?
    let postgresService: PostgresService

    // For syncing state with TabManager
    private weak var tabManager: TabManager?
    private var tabId: UUID?

    var customQuery: String?

    init(
        connection: ConnectionConfig,
        table: TableInfo?,
        postgresService: PostgresService,
        tabManager: TabManager? = nil,
        tabId: UUID? = nil,
        customQuery: String? = nil
    ) {
        self.connectionConfig = connection
        self.tableInfo = table
        self.postgresService = postgresService
        self.tabManager = tabManager
        self.tabId = tabId
        self.customQuery = customQuery
    }

    var schemaName: String {
        if let info = queryInfo, let schema = info.schemaName {
            return schema
        }
        return tableInfo?.schema ?? "public"
    }

    var tableName: String {
        if let info = queryInfo, let table = info.tableName {
            return table
        }
        return tableInfo?.name ?? ""
    }

    var isEditable: Bool {
        if let info = queryInfo {
            return info.isEditable && !tableData.primaryKeyColumns.isEmpty
        }
        return tableInfo != nil && !tableData.primaryKeyColumns.isEmpty
    }

    var nonEditableReason: String? {
        if let info = queryInfo, !info.isEditable {
            return info.nonEditableReason
        }
        if tableData.primaryKeyColumns.isEmpty {
            return "Table has no primary key - updates cannot be safely generated"
        }
        return nil
    }

    func loadData() async {
        guard let table = tableInfo else {
            if let query = customQuery {
                await executeCustomQuery(query)
            }
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let columns = try await postgresService.getColumns(
                configId: connectionConfig.id,
                schema: table.schema,
                table: table.name
            )

            let totalCount = try await postgresService.getTableRowCount(
                configId: connectionConfig.id,
                schema: table.schema,
                table: table.name
            )

            let rows = try await postgresService.fetchTableData(
                configId: connectionConfig.id,
                schema: table.schema,
                table: table.name,
                columns: columns,
                page: tableData.currentPage,
                pageSize: tableData.pageSize,
                sortColumn: sortColumnName,
                sortAscending: sortDirection == .ascending
            )

            let pkColumns = columns.filter { $0.isPrimaryKey }.map { $0.name }

            tableData = TableData(
                columns: columns,
                rows: rows,
                primaryKeyColumns: pkColumns,
                totalRowCount: totalCount,
                currentPage: tableData.currentPage,
                pageSize: tableData.pageSize
            )
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func executeCustomQuery(_ query: String) async {
        customQuery = query
        queryInfo = QueryInfo.analyze(query: query)

        isLoading = true
        errorMessage = nil
        pendingChanges.clear()

        do {
            let (columns, rows) = try await postgresService.executeQuery(
                configId: connectionConfig.id,
                sql: query
            )

            if let info = queryInfo, info.isEditable, let schema = info.schemaName, let table = info.tableName {
                let tableColumns = try await postgresService.getColumns(
                    configId: connectionConfig.id,
                    schema: schema,
                    table: table
                )

                let pkColumns = tableColumns.filter { $0.isPrimaryKey }.map { $0.name }

                let mergedColumns = columns.enumerated().map { index, col -> ColumnInfo in
                    if let tableCol = tableColumns.first(where: { $0.name == col.name }) {
                        return tableCol
                    }
                    return col
                }

                tableData = TableData(
                    columns: mergedColumns,
                    rows: rows,
                    primaryKeyColumns: pkColumns,
                    totalRowCount: rows.count,
                    currentPage: 1,
                    pageSize: rows.count
                )
            } else {
                tableData = TableData(
                    columns: columns,
                    rows: rows,
                    primaryKeyColumns: [],
                    totalRowCount: rows.count,
                    currentPage: 1,
                    pageSize: rows.count
                )
            }
        } catch {
            errorMessage = "Query failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func goToPage(_ page: Int) async {
        guard page >= 1 && page <= tableData.totalPages else { return }
        tableData.currentPage = page
        pendingChanges.clear()
        await loadData()
    }

    func nextPage() async {
        await goToPage(tableData.currentPage + 1)
    }

    func previousPage() async {
        await goToPage(tableData.currentPage - 1)
    }

    func updateCell(rowIndex: Int, columnIndex: Int, newValue: String) {
        guard rowIndex < tableData.rows.count,
              columnIndex < tableData.columns.count else { return }

        let column = tableData.columns[columnIndex]
        let originalValue = tableData.rows[rowIndex][columnIndex]
        let newCellValue = CellValue.from(string: newValue, forType: column.dataType, wasNull: newValue.uppercased() == "NULL")

        var pkValues: [String: CellValue] = [:]
        for pkColumn in tableData.primaryKeyColumns {
            if let pkIndex = tableData.columns.firstIndex(where: { $0.name == pkColumn }) {
                pkValues[pkColumn] = tableData.rows[rowIndex][pkIndex]
            }
        }

        let edit = CellEdit(
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            columnName: column.name,
            originalValue: originalValue,
            newValue: newCellValue,
            primaryKeyValues: pkValues,
            tableName: tableName,
            schemaName: schemaName
        )

        pendingChanges.addEdit(edit)
        tableData.rows[rowIndex][columnIndex] = newCellValue
    }

    func rollbackAll() {
        for edit in pendingChanges.edits {
            if edit.rowIndex < tableData.rows.count && edit.columnIndex < tableData.columns.count {
                tableData.rows[edit.rowIndex][edit.columnIndex] = edit.originalValue
            }
        }
        pendingChanges.clear()
    }

    func rollbackEdit(_ edit: CellEdit) {
        if edit.rowIndex < tableData.rows.count && edit.columnIndex < tableData.columns.count {
            tableData.rows[edit.rowIndex][edit.columnIndex] = edit.originalValue
        }
        if let index = pendingChanges.edits.firstIndex(of: edit) {
            pendingChanges.removeEdit(at: index)
        }
    }

    func previewSQL() -> String {
        pendingChanges.generateAllSQL()
    }

    func pushChanges() async -> Bool {
        guard pendingChanges.hasChanges else { return true }

        isLoading = true
        errorMessage = nil

        let sql = pendingChanges.generateAllSQL()

        do {
            _ = try await postgresService.executeUpdate(
                configId: connectionConfig.id,
                sql: sql
            )
            pendingChanges.clear()
            isLoading = false
            return true
        } catch {
            errorMessage = "Push failed: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    func getCellDisplayValue(rowIndex: Int, columnIndex: Int) -> CellValue {
        guard rowIndex < tableData.rows.count,
              columnIndex < tableData.columns.count else {
            return .null
        }
        return tableData.rows[rowIndex][columnIndex]
    }

    func isCellModified(rowIndex: Int, columnIndex: Int) -> Bool {
        pendingChanges.editForCell(rowIndex: rowIndex, columnIndex: columnIndex) != nil
    }

    // MARK: - Sorting

    var sortColumnName: String? {
        guard let index = sortColumnIndex, index < tableData.columns.count else {
            return nil
        }
        return tableData.columns[index].name
    }

    func toggleSort(columnIndex: Int) {
        if sortColumnIndex == columnIndex {
            sortDirection = sortDirection.toggled
        } else {
            sortColumnIndex = columnIndex
            sortDirection = .ascending
        }
        syncSortToTabManager()
        Task {
            await loadData()
        }
    }

    func clearSort() {
        sortColumnIndex = nil
        sortDirection = .ascending
        syncSortToTabManager()
        Task {
            await loadData()
        }
    }

    private func syncSortToTabManager() {
        guard let tabManager = tabManager, let tabId = tabId else { return }
        tabManager.updateTabSort(tabId, columnIndex: sortColumnIndex, ascending: sortDirection == .ascending)
    }
}
