import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.connectionStore.connections) { connection in
                    ConnectionItemView(
                        connection: connection,
                        viewModel: viewModel
                    )
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button(action: {
                    ConnectionWindowController.shared.showConnectionForm(
                        connectionStore: viewModel.connectionStore,
                        postgresService: viewModel.postgresService
                    )
                }) {
                    Label("Add Connection", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()
            }
            .padding(8)
        }
        .frame(minWidth: 220)
    }
}

struct ConnectionItemView: View {
    let connection: ConnectionConfig
    @ObservedObject var viewModel: AppViewModel

    @State private var isExpanded = true
    @State private var isHovering = false

    var isConnected: Bool {
        viewModel.isConnected(connection.id)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isConnected {
                connectionContent
            } else {
                Text("Not connected")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.leading, 8)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: connection.iconName)
                    .foregroundColor(connection.iconColor.color)
                    .font(.system(size: 16, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .fontWeight(.medium)
                    Text(connection.connectionString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isHovering {
                    connectionButtons
                }

                Circle()
                    .fill(isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .contextMenu {
            contextMenuContent
        }
    }

    @ViewBuilder
    var connectionContent: some View {
        if let schemas = viewModel.schemas[connection.id] {
            ForEach(schemas) { schema in
                SchemaItemView(
                    schema: schema,
                    connection: connection,
                    viewModel: viewModel
                )
            }
        }

        Button(action: { viewModel.openQueryEditor(connection: connection) }) {
            Label("New Query", systemImage: "terminal")
        }
        .buttonStyle(.borderless)
        .padding(.leading, 8)
        .padding(.top, 4)
    }

    @ViewBuilder
    var connectionButtons: some View {
        if isConnected {
            Button(action: {
                Task { await viewModel.disconnect(from: connection) }
            }) {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Disconnect")
        } else {
            Button(action: {
                Task { await viewModel.connect(to: connection) }
            }) {
                Image(systemName: "bolt.circle")
                    .foregroundColor(.green)
            }
            .buttonStyle(.borderless)
            .help("Connect")
        }
    }

    @ViewBuilder
    var contextMenuContent: some View {
        if isConnected {
            Button("Disconnect") {
                Task { await viewModel.disconnect(from: connection) }
            }
            Button("New Query") {
                viewModel.openQueryEditor(connection: connection)
            }
        } else {
            Button("Connect") {
                Task { await viewModel.connect(to: connection) }
            }
        }

        Divider()

        Button("Edit Connection") {
            ConnectionWindowController.shared.showConnectionForm(
                connectionStore: viewModel.connectionStore,
                postgresService: viewModel.postgresService,
                existingConnection: connection
            )
        }

        Button("Remove Connection", role: .destructive) {
            Task {
                await viewModel.disconnect(from: connection)
                viewModel.connectionStore.removeConnection(connection.id)
            }
        }
    }
}

struct SchemaItemView: View {
    let schema: SchemaInfo
    let connection: ConnectionConfig
    @ObservedObject var viewModel: AppViewModel

    @State private var isExpanded = true

    var tables: [TableInfo] {
        viewModel.tables[connection.id]?[schema.name] ?? []
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(tables) { table in
                TableItemView(
                    table: table,
                    connection: connection,
                    viewModel: viewModel
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundColor(.blue)
                Text(schema.name)
            }
        }
    }
}

struct TableItemView: View {
    let table: TableInfo
    let connection: ConnectionConfig
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: table.type == .view ? "eye" : "tablecells")
                .foregroundColor(table.type == .view ? .purple : .orange)
            Text(table.name)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openTable(table, connection: connection)
        }
        .contextMenu {
            Button("Open in New Tab") {
                viewModel.openTable(table, connection: connection)
            }
        }
    }
}
