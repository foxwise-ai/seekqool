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

    // Autocomplete state
    @State private var cursorPosition: Int = 0
    @State private var cursorScreenPosition: CGPoint = .zero
    @State private var triggerCompletion: Bool = false
    @State private var completions: [CompletionItem] = []
    @State private var selectedCompletionIndex: Int = 0
    @StateObject private var autoCompleteProvider: SQLAutoCompleteProvider

    init(connection: ConnectionConfig, postgresService: PostgresService, tabQuery: Binding<String?>, resultsViewModel: TableDataViewModel) {
        self.connection = connection
        self.postgresService = postgresService
        self._tabQuery = tabQuery
        self.resultsViewModel = resultsViewModel
        self._autoCompleteProvider = StateObject(wrappedValue: SQLAutoCompleteProvider(
            postgresService: postgresService,
            connectionId: connection.id
        ))
    }

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
            // Load tables for autocomplete
            Task {
                await autoCompleteProvider.loadTables()
            }
        }
        .onChange(of: queryText) { _, newValue in
            tabQuery = newValue
        }
        .onChange(of: triggerCompletion) { _, triggered in
            if triggered {
                Task {
                    completions = await autoCompleteProvider.getCompletions(for: queryText, cursorPosition: cursorPosition)
                    selectedCompletionIndex = 0
                }
            } else {
                completions = []
            }
        }
    }

    var editorPane: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                editorToolbar

                Divider()

                SQLTextView(
                    text: $queryText,
                    errorRange: $errorRange,
                    cursorPosition: $cursorPosition,
                    triggerCompletion: $triggerCompletion,
                    cursorScreenPosition: $cursorScreenPosition,
                    onArrowUp: {
                        if selectedCompletionIndex > 0 {
                            selectedCompletionIndex -= 1
                        }
                    },
                    onArrowDown: {
                        if selectedCompletionIndex < min(completions.count, 8) - 1 {
                            selectedCompletionIndex += 1
                        }
                    },
                    onEnter: {
                        if !completions.isEmpty && selectedCompletionIndex < completions.count {
                            insertCompletion(completions[selectedCompletionIndex])
                        }
                    }
                )
            }

            // Completion popup positioned near cursor
            if !completions.isEmpty {
                completionPopup
                    .offset(x: cursorScreenPosition.x + 8, y: cursorScreenPosition.y + 45)
            }
        }
    }

    var completionPopup: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(completions.prefix(8).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Image(systemName: item.icon)
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Text(item.text)
                        .fontWeight(index == selectedCompletionIndex ? .semibold : .regular)

                    Spacer()

                    Text(item.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(index == selectedCompletionIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    insertCompletion(item)
                }
            }
        }
        .frame(width: 250)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    func insertCompletion(_ item: CompletionItem) {
        // Find the start of the current word
        let prefix = String(queryText.prefix(cursorPosition))
        let wordStart = prefix.lastIndex(where: { $0 == "." || $0 == " " || $0 == "\n" || $0 == "(" })
            .map { prefix.distance(from: prefix.startIndex, to: prefix.index(after: $0)) } ?? 0

        // Replace the partial word with the completion
        let before = String(queryText.prefix(wordStart))
        let after = String(queryText.dropFirst(cursorPosition))
        queryText = before + item.text + after

        // Dismiss completions
        triggerCompletion = false
        completions = []
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
        let isDeleted = dataViewModel.isRowDeleted(rowIndex: rowIndex)
        let visibleIndices = dataViewModel.tableData.visibleColumnIndices

        return HStack(spacing: 0) {
            ForEach(Array(visibleIndices.enumerated()), id: \.element) { visibleIndex, actualColIndex in
                resultCellView(rowIndex: rowIndex, colIndex: actualColIndex, isDeleted: isDeleted, isLastColumn: visibleIndex >= visibleIndices.count - 1)
            }
        }
        .border(Color(NSColor.separatorColor).opacity(0.3), width: 0.5)
    }

    @ViewBuilder
    func resultCellView(rowIndex: Int, colIndex: Int, isDeleted: Bool, isLastColumn: Bool) -> some View {
        let column = dataViewModel.tableData.columns[colIndex]
        let cellValue = dataViewModel.tableData.rows[rowIndex][colIndex]
        let isModified = dataViewModel.isCellModified(rowIndex: rowIndex, columnIndex: colIndex)
        let isSelected = selectedCell?.row == rowIndex && selectedCell?.col == colIndex
        let isEditing = editingCell?.row == rowIndex && editingCell?.col == colIndex

        let bgColor: Color = {
            if isDeleted { return Color.red.opacity(0.1) }
            if isEditing { return Color.accentColor.opacity(0.15) }
            if isSelected { return Color.accentColor.opacity(0.1) }
            if isModified { return Color.orange.opacity(0.2) }
            return rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3)
        }()

        ZStack {
            if isEditing && dataViewModel.isEditable && !isDeleted {
                TextField("", text: $editText, onCommit: {
                    dataViewModel.updateCell(rowIndex: rowIndex, columnIndex: colIndex, newValue: editText)
                    editingCell = nil
                })
                .textFieldStyle(.plain)
                .font(.caption)
            } else {
                Text(cellValue.description)
                    .font(.caption)
                    .foregroundColor(isDeleted ? .red : (cellValue.isNull ? .secondary : .primary))
                    .italic(cellValue.isNull)
                    .strikethrough(isDeleted, color: .red)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: columnWidth(for: column), alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(bgColor)
        .border(Color.accentColor, width: isEditing ? 2 : (isSelected ? 1 : 0))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if dataViewModel.isEditable && !isDeleted {
                editingCell = (rowIndex, colIndex)
                editText = cellValue.isNull ? "" : cellValue.description
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            if let editing = editingCell, (editing.row != rowIndex || editing.col != colIndex) {
                if !editText.isEmpty || dataViewModel.tableData.rows[editing.row][editing.col].isNull {
                    dataViewModel.updateCell(rowIndex: editing.row, columnIndex: editing.col, newValue: editText)
                }
                editingCell = nil
            }
            selectedCell = (rowIndex, colIndex)
        })
        .contextMenu {
            resultCellContextMenu(rowIndex: rowIndex, colIndex: colIndex, cellValue: cellValue, isDeleted: isDeleted)
        }

        if !isLastColumn {
            Divider()
        }
    }

    @ViewBuilder
    func resultCellContextMenu(rowIndex: Int, colIndex: Int, cellValue: CellValue, isDeleted: Bool) -> some View {
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cellValue.description, forType: .string)
        }
        if dataViewModel.isEditable {
            Divider()
            if isDeleted {
                Button("Undo Delete") {
                    dataViewModel.undoDeleteRow(rowIndex: rowIndex)
                }
            } else {
                Button("Edit") {
                    editingCell = (rowIndex, colIndex)
                    editText = cellValue.isNull ? "" : cellValue.description
                }
                Button("Set NULL") {
                    dataViewModel.updateCell(rowIndex: rowIndex, columnIndex: colIndex, newValue: "NULL")
                }
                Divider()
                Button {
                    dataViewModel.deleteRow(rowIndex: rowIndex)
                } label: {
                    Label("Delete Row", systemImage: "trash")
                }
            }
        }
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
