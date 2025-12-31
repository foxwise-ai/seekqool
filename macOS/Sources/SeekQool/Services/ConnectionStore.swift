import Foundation
import SwiftUI

@MainActor
class ConnectionStore: ObservableObject {
    @Published var connections: [ConnectionConfig] = []
    @Published var activeConnectionIds: Set<UUID> = []

    private let saveKey = "seekqool.connections"
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("SeekQool", isDirectory: true)

        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        self.fileURL = appFolder.appendingPathComponent("connections.json")
        loadConnections()
    }

    func loadConnections() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            connections = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            connections = try JSONDecoder().decode([ConnectionConfig].self, from: data)
        } catch {
            print("Failed to load connections: \(error)")
            connections = []
        }
    }

    func saveConnections() {
        do {
            let data = try JSONEncoder().encode(connections)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save connections: \(error)")
        }
    }

    func addConnection(_ config: ConnectionConfig) {
        connections.append(config)
        saveConnections()
    }

    func updateConnection(_ config: ConnectionConfig) {
        if let index = connections.firstIndex(where: { $0.id == config.id }) {
            connections[index] = config
            saveConnections()
        }
    }

    func removeConnection(_ id: UUID) {
        connections.removeAll { $0.id == id }
        activeConnectionIds.remove(id)
        saveConnections()
    }

    func setActive(_ id: UUID, active: Bool) {
        if active {
            activeConnectionIds.insert(id)
        } else {
            activeConnectionIds.remove(id)
        }
    }

    func isActive(_ id: UUID) -> Bool {
        activeConnectionIds.contains(id)
    }

    func connection(for id: UUID) -> ConnectionConfig? {
        connections.first { $0.id == id }
    }

    func generateUniqueIconColor() -> IconColor {
        let usedColors = Set(connections.map { $0.iconColor })
        let availableColors = IconColor.allCases.filter { !usedColors.contains($0) }
        return availableColors.randomElement() ?? IconColor.allCases.randomElement()!
    }

    func generateUniqueIcon() -> String {
        let usedIcons = Set(connections.map { $0.iconName })
        let available = availableIcons.filter { !usedIcons.contains($0) }
        return available.randomElement() ?? availableIcons.randomElement()!
    }
}
