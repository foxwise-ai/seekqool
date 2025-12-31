import Foundation
import SwiftUI

enum TabType: Equatable {
    case tableView(table: TableInfo)
    case queryEditor
}

struct AppTab: Identifiable, Hashable {
    let id: UUID
    let connectionId: UUID
    let type: TabType
    var title: String
    var customQuery: String?
    var sortColumnIndex: Int?
    var sortAscending: Bool = true

    init(
        id: UUID = UUID(),
        connectionId: UUID,
        type: TabType,
        title: String? = nil,
        customQuery: String? = nil,
        sortColumnIndex: Int? = nil,
        sortAscending: Bool = true
    ) {
        self.id = id
        self.connectionId = connectionId
        self.type = type
        self.customQuery = customQuery
        self.sortColumnIndex = sortColumnIndex
        self.sortAscending = sortAscending

        switch type {
        case .tableView(let table):
            self.title = title ?? table.name
        case .queryEditor:
            self.title = title ?? "Query"
        }
    }

    static func == (lhs: AppTab, rhs: AppTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Session State Persistence

struct SavedTabState: Codable {
    let id: UUID
    let connectionId: UUID
    let tabType: SavedTabType
    let title: String
    let customQuery: String?
    let sortColumnIndex: Int?
    let sortAscending: Bool
}

enum SavedTabType: Codable {
    case tableView(schema: String, tableName: String, tableType: String)
    case queryEditor
}

struct ConnectionSessionState: Codable {
    let connectionId: UUID
    var tabs: [SavedTabState]
    var selectedTabId: UUID?
}

class SessionStateManager {
    static let shared = SessionStateManager()
    private let userDefaults = UserDefaults.standard
    private let stateKey = "seekqool.sessionStates"

    private init() {}

    func saveState(for connectionId: UUID, tabs: [AppTab], selectedTabId: UUID?) {
        var allStates = loadAllStates()

        let savedTabs = tabs.filter { $0.connectionId == connectionId }.map { tab -> SavedTabState in
            let tabType: SavedTabType
            switch tab.type {
            case .tableView(let table):
                tabType = .tableView(schema: table.schema, tableName: table.name, tableType: table.type.rawValue)
            case .queryEditor:
                tabType = .queryEditor
            }

            return SavedTabState(
                id: tab.id,
                connectionId: tab.connectionId,
                tabType: tabType,
                title: tab.title,
                customQuery: tab.customQuery,
                sortColumnIndex: tab.sortColumnIndex,
                sortAscending: tab.sortAscending
            )
        }

        let state = ConnectionSessionState(
            connectionId: connectionId,
            tabs: savedTabs,
            selectedTabId: selectedTabId
        )

        allStates[connectionId.uuidString] = state
        saveAllStates(allStates)
    }

    func loadState(for connectionId: UUID) -> ConnectionSessionState? {
        let allStates = loadAllStates()
        return allStates[connectionId.uuidString]
    }

    func clearState(for connectionId: UUID) {
        var allStates = loadAllStates()
        allStates.removeValue(forKey: connectionId.uuidString)
        saveAllStates(allStates)
    }

    private func loadAllStates() -> [String: ConnectionSessionState] {
        guard let data = userDefaults.data(forKey: stateKey),
              let states = try? JSONDecoder().decode([String: ConnectionSessionState].self, from: data) else {
            return [:]
        }
        return states
    }

    private func saveAllStates(_ states: [String: ConnectionSessionState]) {
        if let data = try? JSONEncoder().encode(states) {
            userDefaults.set(data, forKey: stateKey)
        }
    }
}

@MainActor
class TabManager: ObservableObject {
    @Published var tabs: [AppTab] = []
    @Published var selectedTabId: UUID?

    private let sessionManager = SessionStateManager.shared

    var selectedTab: AppTab? {
        guard let id = selectedTabId else { return nil }
        return tabs.first { $0.id == id }
    }

    func openTab(_ tab: AppTab) {
        if let existing = tabs.first(where: { $0.id == tab.id }) {
            selectedTabId = existing.id
        } else {
            tabs.append(tab)
            selectedTabId = tab.id
        }
        saveState(for: tab.connectionId)
    }

    func openTableTab(connection: ConnectionConfig, table: TableInfo) {
        let existingTab = tabs.first {
            if case .tableView(let t) = $0.type {
                return $0.connectionId == connection.id && t.fullName == table.fullName
            }
            return false
        }

        if let existing = existingTab {
            selectedTabId = existing.id
        } else {
            let tab = AppTab(
                connectionId: connection.id,
                type: .tableView(table: table)
            )
            tabs.append(tab)
            selectedTabId = tab.id
        }
        saveState(for: connection.id)
    }

    func openQueryTab(connection: ConnectionConfig) {
        let queryCount = tabs.filter {
            if case .queryEditor = $0.type {
                return $0.connectionId == connection.id
            }
            return false
        }.count

        let tab = AppTab(
            connectionId: connection.id,
            type: .queryEditor,
            title: "Query \(queryCount + 1)"
        )
        tabs.append(tab)
        selectedTabId = tab.id
        saveState(for: connection.id)
    }

    func closeTab(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let connectionId = tabs[index].connectionId
        tabs.remove(at: index)

        if selectedTabId == tabId {
            if !tabs.isEmpty {
                let newIndex = min(index, tabs.count - 1)
                selectedTabId = tabs[newIndex].id
            } else {
                selectedTabId = nil
            }
        }
        saveState(for: connectionId)
    }

    func closeAllTabs(forConnection connectionId: UUID) {
        tabs.removeAll { $0.connectionId == connectionId }
        if let selected = selectedTabId, !tabs.contains(where: { $0.id == selected }) {
            selectedTabId = tabs.first?.id
        }
        // Don't save state here - connection is being disconnected
    }

    func updateTabTitle(_ tabId: UUID, title: String) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].title = title
            saveState(for: tabs[index].connectionId)
        }
    }

    func updateTabQuery(_ tabId: UUID, query: String) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].customQuery = query
            saveState(for: tabs[index].connectionId)
        }
    }

    func updateTabSort(_ tabId: UUID, columnIndex: Int?, ascending: Bool) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].sortColumnIndex = columnIndex
            tabs[index].sortAscending = ascending
            saveState(for: tabs[index].connectionId)
        }
    }

    func selectTab(_ tabId: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
        selectedTabId = tabId
        saveState(for: tab.connectionId)
    }

    // MARK: - Session State

    func restoreState(for connectionId: UUID) {
        guard let state = sessionManager.loadState(for: connectionId) else { return }

        for savedTab in state.tabs {
            let tabType: TabType
            switch savedTab.tabType {
            case .tableView(let schema, let tableName, let tableTypeStr):
                let tableType: TableInfo.TableType = tableTypeStr == "VIEW" ? .view : .table
                let table = TableInfo(schema: schema, name: tableName, type: tableType)
                tabType = .tableView(table: table)
            case .queryEditor:
                tabType = .queryEditor
            }

            let tab = AppTab(
                id: savedTab.id,
                connectionId: savedTab.connectionId,
                type: tabType,
                title: savedTab.title,
                customQuery: savedTab.customQuery,
                sortColumnIndex: savedTab.sortColumnIndex,
                sortAscending: savedTab.sortAscending
            )
            tabs.append(tab)
        }

        if let selectedId = state.selectedTabId, tabs.contains(where: { $0.id == selectedId }) {
            selectedTabId = selectedId
        } else if let firstTab = tabs.first(where: { $0.connectionId == connectionId }) {
            selectedTabId = firstTab.id
        }
    }

    private func saveState(for connectionId: UUID) {
        sessionManager.saveState(for: connectionId, tabs: tabs, selectedTabId: selectedTabId)
    }
}
