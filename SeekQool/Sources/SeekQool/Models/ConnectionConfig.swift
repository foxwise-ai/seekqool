import Foundation
import SwiftUI

struct ConnectionConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var database: String
    var username: String
    var password: String
    var iconName: String
    var iconColor: IconColor

    init(
        id: UUID = UUID(),
        name: String,
        host: String = "localhost",
        port: Int = 5432,
        database: String = "postgres",
        username: String = "postgres",
        password: String = "",
        iconName: String = "cylinder.split.1x2",
        iconColor: IconColor = .blue
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.password = password
        self.iconName = iconName
        self.iconColor = iconColor
    }

    var connectionString: String {
        "postgres://\(username)@\(host):\(port)/\(database)"
    }
}

enum IconColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}

let availableIcons = [
    "cylinder.split.1x2",
    "externaldrive",
    "server.rack",
    "square.stack.3d.up",
    "cube",
    "shippingbox",
    "archivebox",
    "tray.2",
    "folder",
    "doc.on.doc",
    "flame",
    "bolt",
    "star",
    "heart",
    "leaf",
    "drop",
    "snowflake",
    "moon",
    "sun.max",
    "cloud"
]
