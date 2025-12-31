import SwiftUI

struct TableDataView: View {
    @StateObject var dataViewModel: TableDataViewModel
    @State private var editingCell: (row: Int, col: Int)?
    @State private var editText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if dataViewModel.isLoading {
                loadingView
            } else if let error = dataViewModel.errorMessage {
                errorView(error)
            } else if dataViewModel.tableData.columns.isEmpty {
                emptyView
            } else {
                tableContent
            }

            Divider()

            statusBar
        }
        .task {
            // Only load if we don't have data yet (prevents reload on tab switch)
            if dataViewModel.tableData.columns.isEmpty && !dataViewModel.isLoading {
                await dataViewModel.loadData()
            }
        }
    }

    var toolbar: some View {
        HStack(spacing: 12) {
            if !dataViewModel.isEditable {
                if let reason = dataViewModel.nonEditableReason {
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            if dataViewModel.pendingChanges.hasChanges {
                Text("\(dataViewModel.pendingChanges.changeCount) pending change(s)")
                    .font(.caption)
                    .foregroundColor(.orange)

                Button(action: { dataViewModel.showSQLPreview = true }) {
                    Label("Preview SQL", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Button(action: { dataViewModel.rollbackAll() }) {
                    Label("Rollback All", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: {
                    dataViewModel.showSQLPreview = true
                }) {
                    Label("Push Changes", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            Button(action: {
                Task { await dataViewModel.loadData() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(isPresented: $dataViewModel.showSQLPreview) {
            SQLPreviewSheet(dataViewModel: dataViewModel)
        }
    }

    var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading data...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.secondary)
            Button("Retry") {
                Task { await dataViewModel.loadData() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No data")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var tableContent: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section(header: headerRow) {
                    ForEach(Array(dataViewModel.tableData.rows.enumerated()), id: \.offset) { rowIndex, row in
                        dataRow(rowIndex: rowIndex, row: row)
                    }
                }
            }
        }
    }

    var headerRow: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 50, alignment: .center)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

            let visibleIndices = dataViewModel.tableData.visibleColumnIndices
            ForEach(Array(visibleIndices.enumerated()), id: \.element) { visibleIndex, actualIndex in
                let column = dataViewModel.tableData.columns[actualIndex]
                let isSorted = dataViewModel.sortColumnIndex == actualIndex

                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if column.isPrimaryKey {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.yellow)
                            }
                            Text(column.name)
                                .fontWeight(.semibold)
                        }
                        Text(column.dataType)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isSorted {
                        Image(systemName: dataViewModel.sortDirection == .ascending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(width: columnWidth(for: column), alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isSorted ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .contentShape(Rectangle())
                .onTapGesture {
                    dataViewModel.toggleSort(columnIndex: actualIndex)
                }

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
                            commitEdit(rowIndex: rowIndex, colIndex: actualColIndex)
                        })
                        .textFieldStyle(.plain)
                        .onExitCommand {
                            cancelEdit()
                        }
                    } else {
                        Text(cellValue.description)
                            .foregroundColor(cellValue.isNull ? .secondary : .primary)
                            .italic(cellValue.isNull)
                    }
                }
                .frame(width: columnWidth(for: column), alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(cellBackground(isModified: isModified, rowIndex: rowIndex))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if dataViewModel.isEditable {
                        startEditing(rowIndex: rowIndex, colIndex: actualColIndex, value: cellValue)
                    }
                }
                .contextMenu {
                    if dataViewModel.isEditable {
                        Button("Edit") {
                            startEditing(rowIndex: rowIndex, colIndex: actualColIndex, value: cellValue)
                        }
                        Button("Set to NULL") {
                            dataViewModel.updateCell(rowIndex: rowIndex, columnIndex: actualColIndex, newValue: "NULL")
                        }
                        if isModified, let edit = dataViewModel.pendingChanges.editForCell(rowIndex: rowIndex, columnIndex: actualColIndex) {
                            Divider()
                            Button("Rollback This Cell") {
                                dataViewModel.rollbackEdit(edit)
                            }
                        }
                    }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cellValue.description, forType: .string)
                    }
                }

                if visibleIndex < visibleIndices.count - 1 {
                    Divider()
                }
            }
        }
        .border(Color(NSColor.separatorColor).opacity(0.5), width: 0.5)
    }

    func cellBackground(isModified: Bool, rowIndex: Int) -> Color {
        if isModified {
            return Color.orange.opacity(0.2)
        }
        return rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3)
    }

    func columnWidth(for column: ColumnInfo) -> CGFloat {
        let baseWidth: CGFloat = 120
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

        return baseWidth
    }

    func startEditing(rowIndex: Int, colIndex: Int, value: CellValue) {
        editingCell = (rowIndex, colIndex)
        editText = value.isNull ? "" : value.description
    }

    func commitEdit(rowIndex: Int, colIndex: Int) {
        dataViewModel.updateCell(rowIndex: rowIndex, columnIndex: colIndex, newValue: editText)
        editingCell = nil
        editText = ""
    }

    func cancelEdit() {
        editingCell = nil
        editText = ""
    }

    var statusBar: some View {
        HStack {
            Text("\(dataViewModel.tableData.totalRowCount) total rows")
                .font(.caption)
                .foregroundColor(.secondary)

            if let sortCol = dataViewModel.sortColumnIndex,
               sortCol < dataViewModel.tableData.columns.count {
                let colName = dataViewModel.tableData.columns[sortCol].name
                let direction = dataViewModel.sortDirection == .ascending ? "↑" : "↓"

                HStack(spacing: 4) {
                    Text("Sorted by \(colName) \(direction)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { dataViewModel.clearSort() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear sort")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
            }

            Spacer()

            if dataViewModel.tableData.totalPages > 1 {
                HStack(spacing: 8) {
                    Button(action: {
                        Task { await dataViewModel.previousPage() }
                    }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(dataViewModel.tableData.currentPage <= 1)
                    .buttonStyle(.borderless)

                    Text("Page \(dataViewModel.tableData.currentPage) of \(dataViewModel.tableData.totalPages)")
                        .font(.caption)

                    Button(action: {
                        Task { await dataViewModel.nextPage() }
                    }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(dataViewModel.tableData.currentPage >= dataViewModel.tableData.totalPages)
                    .buttonStyle(.borderless)
                }
            }

            Text("\(dataViewModel.tableData.pageSize) rows per page")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct SQLPreviewSheet: View {
    @ObservedObject var dataViewModel: TableDataViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPushing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review SQL Changes")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                Text(dataViewModel.previewSQL())
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            HStack {
                Text("\(dataViewModel.pendingChanges.changeCount) change(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Rollback All") {
                    dataViewModel.rollbackAll()
                    dismiss()
                }
                .tint(.red)

                Button(action: pushChanges) {
                    HStack {
                        if isPushing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Execute")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPushing)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 600, height: 450)
    }

    func pushChanges() {
        isPushing = true
        Task {
            let success = await dataViewModel.pushChanges()
            isPushing = false
            if success {
                dismiss()
                await dataViewModel.loadData()
            }
        }
    }
}
