import SwiftUI

struct QueryEditorView: View {
    let connection: ConnectionConfig
    let postgresService: PostgresService
    @Binding var tabQuery: String?
    @ObservedObject var resultsViewModel: TableDataViewModel

    @State private var queryText: String = ""
    @State private var isExecuting = false
    @State private var executionTime: TimeInterval?
    @State private var showResults = false
    @State private var errorRange: NSRange?

    var body: some View {
        VSplitView {
            editorPane
                .frame(minHeight: 150)

            if showResults || !resultsViewModel.tableData.columns.isEmpty {
                resultsPane
                    .frame(minHeight: 150)
            }
        }
        .onAppear {
            if let saved = tabQuery {
                queryText = saved
            }
            // Show results pane if we have cached results
            if !resultsViewModel.tableData.columns.isEmpty {
                showResults = true
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

            SQLTextView(text: $queryText, errorRange: $errorRange)
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
        errorRange = nil

        Task {
            let startTime = Date()
            await resultsViewModel.executeCustomQuery(trimmed)
            let endTime = Date()
            executionTime = endTime.timeIntervalSince(startTime)
            isExecuting = false

            // If there was an error, highlight the whole query
            if resultsViewModel.errorMessage != nil {
                errorRange = NSRange(location: 0, length: queryText.utf16.count)
            }
        }
    }
}

struct QueryResultsTableView: View {
    @ObservedObject var dataViewModel: TableDataViewModel
    @State private var selectedCell: (row: Int, col: Int)?
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
            let visibleIndices = dataViewModel.tableData.visibleColumnIndices
            ForEach(Array(visibleIndices.enumerated()), id: \.element) { visibleIndex, actualColIndex in
                let column = dataViewModel.tableData.columns[actualColIndex]
                let cellValue = row[actualColIndex]
                let isModified = dataViewModel.isCellModified(rowIndex: rowIndex, columnIndex: actualColIndex)
                let isSelected = selectedCell?.row == rowIndex && selectedCell?.col == actualColIndex
                let isEditing = editingCell?.row == rowIndex && editingCell?.col == actualColIndex

                ZStack {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: columnWidth(for: column), alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    isEditing ? Color.accentColor.opacity(0.15) :
                    isSelected ? Color.accentColor.opacity(0.1) :
                    isModified ? Color.orange.opacity(0.2) :
                    (rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))
                )
                .border(Color.accentColor, width: isEditing ? 2 : (isSelected ? 1 : 0))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if dataViewModel.isEditable {
                        editingCell = (rowIndex, actualColIndex)
                        editText = cellValue.isNull ? "" : cellValue.description
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    // If editing another cell, commit the edit first
                    if let editing = editingCell, (editing.row != rowIndex || editing.col != actualColIndex) {
                        if !editText.isEmpty || dataViewModel.tableData.rows[editing.row][editing.col].isNull {
                            dataViewModel.updateCell(rowIndex: editing.row, columnIndex: editing.col, newValue: editText)
                        }
                        editingCell = nil
                    }
                    selectedCell = (rowIndex, actualColIndex)
                })
                .contextMenu {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cellValue.description, forType: .string)
                    }
                    if dataViewModel.isEditable {
                        Divider()
                        Button("Edit") {
                            editingCell = (rowIndex, actualColIndex)
                            editText = cellValue.isNull ? "" : cellValue.description
                        }
                        Button("Set NULL") {
                            dataViewModel.updateCell(rowIndex: rowIndex, columnIndex: actualColIndex, newValue: "NULL")
                        }
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
