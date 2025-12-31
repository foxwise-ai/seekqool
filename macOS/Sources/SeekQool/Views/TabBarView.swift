import SwiftUI

struct TabBarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.tabManager.tabs) { tab in
                    TabItemView(
                        tab: tab,
                        connection: viewModel.connectionStore.connection(for: tab.connectionId),
                        isSelected: viewModel.tabManager.selectedTabId == tab.id,
                        onSelect: {
                            viewModel.tabManager.selectedTabId = tab.id
                        },
                        onClose: {
                            viewModel.tabManager.closeTab(tab.id)
                        }
                    )
                }

                Spacer()
            }
        }
        .frame(height: 36)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct TabItemView: View {
    let tab: AppTab
    let connection: ConnectionConfig?
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let conn = connection {
                Image(systemName: conn.iconName)
                    .foregroundColor(conn.iconColor.color)
                    .font(.system(size: 12))
            }

            Image(systemName: tabIcon)
                .foregroundColor(.secondary)
                .font(.system(size: 10))

            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)

            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color(NSColor.selectedContentBackgroundColor) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close Tab") { onClose() }
            Button("Close Other Tabs") {
                let otherIds = viewModel.tabManager.tabs.filter { $0.id != tab.id }.map { $0.id }
                for id in otherIds {
                    viewModel.tabManager.closeTab(id)
                }
            }
        }
    }

    @EnvironmentObject var viewModel: AppViewModel

    var tabIcon: String {
        switch tab.type {
        case .tableView(let table):
            return table.type == .view ? "eye" : "tablecells"
        case .queryEditor:
            return "terminal"
        }
    }
}
