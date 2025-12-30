import Foundation
import SwiftUI
import Combine

@MainActor
class AppViewModel: ObservableObject {
    @Published var connectionStore: ConnectionStore
    @Published var tabManager: TabManager
    @Published var postgresService: PostgresService

    @Published var schemas: [UUID: [SchemaInfo]] = [:]
    @Published var tables: [UUID: [String: [TableInfo]]] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    // Cache for TableDataViewModels by tab ID
    private var tableViewModelCache: [UUID: TableDataViewModel] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.connectionStore = ConnectionStore()
        self.tabManager = TabManager()
        self.postgresService = PostgresService()

        // Forward child object changes to trigger SwiftUI updates
        tabManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        connectionStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func connect(to config: ConnectionConfig) async {
        isLoading = true
        errorMessage = nil

        do {
            let success = try await postgresService.connect(config: config)
            if success {
                connectionStore.setActive(config.id, active: true)
                await loadSchemas(for: config.id)
                // Restore previous session state
                tabManager.restoreState(for: config.id)
            }
        } catch {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            showError = true
        }

        isLoading = false
    }

    func disconnect(from config: ConnectionConfig) async {
        await postgresService.disconnect(configId: config.id)
        connectionStore.setActive(config.id, active: false)
        schemas.removeValue(forKey: config.id)
        tables.removeValue(forKey: config.id)
        // Clear cached view models for this connection
        let tabsToRemove = tabManager.tabs.filter { $0.connectionId == config.id }.map { $0.id }
        for tabId in tabsToRemove {
            tableViewModelCache.removeValue(forKey: tabId)
        }
        tabManager.closeAllTabs(forConnection: config.id)
    }

    // MARK: - ViewModel Cache

    func tableDataViewModel(for tab: AppTab, connection: ConnectionConfig, table: TableInfo) -> TableDataViewModel {
        if let cached = tableViewModelCache[tab.id] {
            return cached
        }

        let viewModel = TableDataViewModel(
            connection: connection,
            table: table,
            postgresService: postgresService,
            tabManager: tabManager,
            tabId: tab.id
        )

        // Restore sort state from tab
        if let sortCol = tab.sortColumnIndex {
            viewModel.sortColumnIndex = sortCol
            viewModel.sortDirection = tab.sortAscending ? .ascending : .descending
        }

        tableViewModelCache[tab.id] = viewModel
        return viewModel
    }

    func clearViewModelCache(for tabId: UUID) {
        tableViewModelCache.removeValue(forKey: tabId)
    }

    func loadSchemas(for connectionId: UUID) async {
        do {
            let schemaList = try await postgresService.listSchemas(configId: connectionId)
            schemas[connectionId] = schemaList

            for schema in schemaList {
                await loadTables(for: connectionId, schema: schema.name)
            }
        } catch {
            errorMessage = "Failed to load schemas: \(error.localizedDescription)"
            showError = true
        }
    }

    func loadTables(for connectionId: UUID, schema: String) async {
        do {
            let tableList = try await postgresService.listTables(configId: connectionId, schema: schema)
            if tables[connectionId] == nil {
                tables[connectionId] = [:]
            }
            tables[connectionId]?[schema] = tableList
        } catch {
            errorMessage = "Failed to load tables: \(error.localizedDescription)"
            showError = true
        }
    }

    func openTable(_ table: TableInfo, connection: ConnectionConfig) {
        tabManager.openTableTab(connection: connection, table: table)
    }

    func openQueryEditor(connection: ConnectionConfig) {
        tabManager.openQueryTab(connection: connection)
    }

    func isConnected(_ connectionId: UUID) -> Bool {
        connectionStore.isActive(connectionId)
    }
}
