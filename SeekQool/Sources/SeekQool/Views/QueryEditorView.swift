import SwiftUI

struct QueryEditorView: View {
    let connection: ConnectionConfig
    let postgresService: PostgresService
    @Binding var tabQuery: String?

    @State private var queryText: String = ""
    @StateObject private var resultsViewModel: TableDataViewModel

    @State private var isExecuting = false
    @State private var executionTime: TimeInterval?
    @State private var showResults = false

    init(connection: ConnectionConfig, postgresService: PostgresService, tabQuery: Binding<String?>) {
        self.connection = connection
        self.postgresService = postgresService
        self._tabQuery = tabQuery
        self._resultsViewModel = StateObject(wrappedValue: TableDataViewModel(
            connection: connection,
            table: nil,
            postgresService: postgresService
        ))
    }

    var body: some View {
        VSplitView {
            editorPane
                .frame(minHeight: 150)

            if showResults {
                resultsPane
                    .frame(minHeight: 150)
            }
        }
        .onAppear {
            if let saved = tabQuery {
                queryText = saved
            }
        }
        .onChange(of: queryText) { _, newValue in
            tabQuery = newValue
        }
    }

    var editorPane: some View {
        VStack(spacing: 0) {
            editorToolbar

            Divider()

            TextEditor(text: $queryText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
        }
    }

    var editorToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.iconName)
                .foregroundColor(connection.iconColor.color)

            Text(connection.name)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if let time = executionTime {
                Text(String(format: "%.2fms", time * 1000))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: executeQuery) {
                HStack(spacing: 4) {
                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text("Run")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExecuting)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    var resultsPane: some View {
        VStack(spacing: 0) {
            resultsToolbar

            Divider()

            if resultsViewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = resultsViewModel.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                QueryResultsTableView(dataViewModel: resultsViewModel)
            }
        }
    }

    var resultsToolbar: some View {
        HStack {
            Text("Results")
                .font(.caption)
                .fontWeight(.semibold)

            if let info = resultsViewModel.queryInfo {
                if info.isEditable {
                    Label("Editable", systemImage: "pencil")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if let reason = info.nonEditableReason {
                    Label(reason, systemImage: "lock")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Text("\(resultsViewModel.tableData.rows.count) row(s)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { showResults = false }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    func executeQuery() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isExecuting = true
        showResults = true
        executionTime = nil

        Task {
            let startTime = Date()
            await resultsViewModel.executeCustomQuery(trimmed)
            let endTime = Date()
            executionTime = endTime.timeIntervalSince(startTime)
            isExecuting = false
        }
    }
}

struct QueryResultsTableView: View {
    @ObservedObject var dataViewModel: TableDataViewModel
    @State private var editingCell: (row: Int, col: Int)?
    @State private var editText: String = ""

    var body: some View {
        if dataViewModel.tableData.columns.isEmpty {
            Text("No results")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section(header: headerRow) {
                        ForEach(Array(dataViewModel.tableData.rows.enumerated()), id: \.offset) { rowIndex, row in
                            dataRow(rowIndex: rowIndex, row: row)
                        }
                    }
                }
            }

            if dataViewModel.pendingChanges.hasChanges {
                changesToolbar
            }
        }
    }

    var headerRow: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 40, alignment: .center)
                .padding(.vertical, 6)
                .font(.caption)
                .background(Color(NSColor.controlBackgroundColor))

            ForEach(Array(dataViewModel.tableData.columns.enumerated()), id: \.element.id) { index, column in
                VStack(alignment: .leading, spacing: 1) {
                    Text(column.name)
                        .fontWeight(.medium)
                        .font(.caption)
                    Text(column.dataType)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 150, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))

                if index < dataViewModel.tableData.columns.count - 1 {
                    Divider()
                }
            }
        }
    }

    func dataRow(rowIndex: Int, row: [CellValue]) -> some View {
        HStack(spacing: 0) {
            Text("\(rowIndex + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .center)
                .padding(.vertical, 4)

            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cellValue in
                let isModified = dataViewModel.isCellModified(rowIndex: rowIndex, columnIndex: colIndex)
                let isEditing = editingCell?.row == rowIndex && editingCell?.col == colIndex

                Group {
                    if isEditing && dataViewModel.isEditable {
                        TextField("", text: $editText, onCommit: {
                            dataViewModel.updateCell(rowIndex: rowIndex, columnIndex: colIndex, newValue: editText)
                            editingCell = nil
                        })
                        .textFieldStyle(.plain)
                        .font(.caption)
                    } else {
                        Text(cellValue.description)
                            .font(.caption)
                            .foregroundColor(cellValue.isNull ? .secondary : .primary)
                            .italic(cellValue.isNull)
                    }
                }
                .frame(width: 150, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isModified ? Color.orange.opacity(0.2) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if dataViewModel.isEditable {
                        editingCell = (rowIndex, colIndex)
                        editText = cellValue.isNull ? "" : cellValue.description
                    }
                }

                if colIndex < row.count - 1 {
                    Divider()
                }
            }
        }
        .border(Color(NSColor.separatorColor).opacity(0.3), width: 0.5)
    }

    var changesToolbar: some View {
        HStack {
            Text("\(dataViewModel.pendingChanges.changeCount) pending change(s)")
                .font(.caption)
                .foregroundColor(.orange)

            Spacer()

            Button("Preview SQL") {
                dataViewModel.showSQLPreview = true
            }
            .font(.caption)

            Button("Rollback") {
                dataViewModel.rollbackAll()
            }
            .font(.caption)
            .foregroundColor(.red)

            Button("Push") {
                dataViewModel.showSQLPreview = true
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $dataViewModel.showSQLPreview) {
            SQLPreviewSheet(dataViewModel: dataViewModel)
        }
    }
}
