import Foundation
import SwiftUI

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

    init() {
        self.connectionStore = ConnectionStore()
        self.tabManager = TabManager()
        self.postgresService = PostgresService()
    }

    func connect(to config: ConnectionConfig) async {
        isLoading = true
        errorMessage = nil

        do {
            let success = try await postgresService.connect(config: config)
            if success {
                connectionStore.setActive(config.id, active: true)
                await loadSchemas(for: config.id)
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
        tabManager.closeAllTabs(forConnection: config.id)
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
