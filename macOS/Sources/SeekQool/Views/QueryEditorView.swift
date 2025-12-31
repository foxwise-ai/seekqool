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
        VStack(spacing: 0) {
            if dataViewModel.tableData.columns.isEmpty {
                Text("No results")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section(header: headerRow) {
                                ForEach(Array(dataViewModel.tableData.rows.enumerated()), id: \.offset) { rowIndex, row in
                                    dataRow(rowIndex: rowIndex, row: row)
                                }
                            }
                        }
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                    }
                }
            }

            if dataViewModel.pendingChanges.hasChanges {
                changesToolbar
            }
        }
    }

    func columnWidth(for column: ColumnInfo) -> CGFloat {
        let type = column.dataType.lowercased()
        if type.contains("text") || type.contains("varchar") || type.contains("json") {
            return 200
        }
        if type.contains("uuid") {
            return 280
        }
        if type.contains("timestamp") || type.contains("date") {
            return 180
        }
        if type == "boolean" || type == "bool" {
            return 80
        }
        return 150
    }

    var headerRow: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 50, alignment: .center)
                .padding(.vertical, 6)
                .font(.caption)
                .background(Color(NSColor.controlBackgroundColor))

            let visibleIndices = dataViewModel.tableData.visibleColumnIndices
            ForEach(Array(visibleIndices.enumerated()), id: \.element) { visibleIndex, actualIndex in
                let column = dataViewModel.tableData.columns[actualIndex]
                VStack(alignment: .leading, spacing: 1) {
                    Text(column.name)
                        .fontWeight(.medium)
                        .font(.caption)
                    Text(column.dataType)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: columnWidth(for: column), alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                if visibleIndex < visibleIndices.count - 1 {
                    Divider()
                }
            }
        }
    }

    func dataRow(rowIndex: Int, row: [CellValue]) -> some View {
        HStack(spacing: 0) {
            Text("\(rowIndex + 1)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .center)
                .padding(.vertical, 6)
                .background(rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))

            let visibleIndices = dataViewModel.tableData.visibleColumnIndices
            ForEach(Array(visibleIndices.enumerated()), id: \.element) { visibleIndex, actualColIndex in
                let column = dataViewModel.tableData.columns[actualColIndex]
                let cellValue = row[actualColIndex]
                let isModified = dataViewModel.isCellModified(rowIndex: rowIndex, columnIndex: actualColIndex)
                let isEditing = editingCell?.row == rowIndex && editingCell?.col == actualColIndex

                Group {
                    if isEditing && dataViewModel.isEditable {
                        TextField("", text: $editText, onCommit: {
                            dataViewModel.updateCell(rowIndex: rowIndex, columnIndex: actualColIndex, newValue: editText)
                            editingCell = nil
                        })
                        .textFieldStyle(.plain)
                        .font(.caption)
                    } else {
                        Text(cellValue.description)
                            .font(.caption)
                            .foregroundColor(cellValue.isNull ? .secondary : .primary)
                            .italic(cellValue.isNull)
                            .lineLimit(1)
                    }
                }
                .frame(width: columnWidth(for: column), alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isModified ? Color.orange.opacity(0.2) : (rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3)))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if dataViewModel.isEditable {
                        editingCell = (rowIndex, actualColIndex)
                        editText = cellValue.isNull ? "" : cellValue.description
                    }
                }

                if visibleIndex < visibleIndices.count - 1 {
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
