import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(viewModel: viewModel)
                .frame(width: 260)

            Divider()

            // Main content
            MainContentArea(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}

struct MainContentArea: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.tabManager.tabs.isEmpty {
                TabBarView(viewModel: viewModel)
                    .environmentObject(viewModel)

                Divider()

                tabContent
            } else {
                emptyState
            }
        }
    }

    @ViewBuilder
    var tabContent: some View {
        if let selectedTab = viewModel.tabManager.selectedTab,
           let connection = viewModel.connectionStore.connection(for: selectedTab.connectionId) {
            switch selectedTab.type {
            case .tableView(let table):
                TableDataView(
                    dataViewModel: TableDataViewModel(
                        connection: connection,
                        table: table,
                        postgresService: viewModel.postgresService
                    )
                )
                .id(selectedTab.id)

            case .queryEditor:
                QueryEditorView(
                    connection: connection,
                    postgresService: viewModel.postgresService,
                    tabQuery: queryBinding(for: selectedTab.id)
                )
                .id(selectedTab.id)
            }
        } else {
            emptyState
        }
    }

    func queryBinding(for tabId: UUID) -> Binding<String?> {
        Binding(
            get: {
                viewModel.tabManager.tabs.first { $0.id == tabId }?.customQuery
            },
            set: { newValue in
                viewModel.tabManager.updateTabQuery(tabId, query: newValue ?? "")
            }
        )
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No tabs open")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Connect to a database and click on a table,\nor open a new query tab.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
