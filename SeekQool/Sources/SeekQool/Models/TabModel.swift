import Foundation
import SwiftUI

enum TabType {
    case tableView(table: TableInfo)
    case queryEditor
}

struct AppTab: Identifiable, Hashable {
    let id: UUID
    let connectionId: UUID
    let type: TabType
    var title: String
    var customQuery: String?

    init(
        id: UUID = UUID(),
        connectionId: UUID,
        type: TabType,
        title: String? = nil,
        customQuery: String? = nil
    ) {
        self.id = id
        self.connectionId = connectionId
        self.type = type
        self.customQuery = customQuery

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

@MainActor
class TabManager: ObservableObject {
    @Published var tabs: [AppTab] = []
    @Published var selectedTabId: UUID?

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
    }

    func closeTab(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs.remove(at: index)

        if selectedTabId == tabId {
            if !tabs.isEmpty {
                let newIndex = min(index, tabs.count - 1)
                selectedTabId = tabs[newIndex].id
            } else {
                selectedTabId = nil
            }
        }
    }

    func closeAllTabs(forConnection connectionId: UUID) {
        tabs.removeAll { $0.connectionId == connectionId }
        if let selected = selectedTabId, !tabs.contains(where: { $0.id == selected }) {
            selectedTabId = tabs.first?.id
        }
    }

    func updateTabTitle(_ tabId: UUID, title: String) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].title = title
        }
    }

    func updateTabQuery(_ tabId: UUID, query: String) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].customQuery = query
        }
    }
}
