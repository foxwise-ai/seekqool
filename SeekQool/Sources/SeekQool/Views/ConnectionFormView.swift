import SwiftUI
import AppKit

struct ConnectionFormView: View {
    let connectionStore: ConnectionStore
    let postgresService: PostgresService
    let existingConnection: ConnectionConfig?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var database: String
    @State private var username: String
    @State private var password: String
    @State private var selectedIcon: String
    @State private var selectedColor: IconColor

    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    init(connectionStore: ConnectionStore, postgresService: PostgresService, existingConnection: ConnectionConfig?) {
        self.connectionStore = connectionStore
        self.postgresService = postgresService
        self.existingConnection = existingConnection

        if let conn = existingConnection {
            _name = State(initialValue: conn.name)
            _host = State(initialValue: conn.host)
            _port = State(initialValue: String(conn.port))
            _database = State(initialValue: conn.database)
            _username = State(initialValue: conn.username)
            _password = State(initialValue: conn.password)
            _selectedIcon = State(initialValue: conn.iconName)
            _selectedColor = State(initialValue: conn.iconColor)
        } else {
            _name = State(initialValue: "")
            _host = State(initialValue: "localhost")
            _port = State(initialValue: "5432")
            _database = State(initialValue: "postgres")
            _username = State(initialValue: "postgres")
            _password = State(initialValue: "")
            _selectedIcon = State(initialValue: connectionStore.generateUniqueIcon())
            _selectedColor = State(initialValue: connectionStore.generateUniqueIconColor())
        }
    }

    var isEditing: Bool {
        existingConnection != nil
    }

    var isValid: Bool {
        !name.isEmpty && !host.isEmpty && !database.isEmpty && !username.isEmpty && (Int(port) != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: selectedIcon)
                    .font(.system(size: 24))
                    .foregroundColor(selectedColor.color)
                    .frame(width: 40, height: 40)
                    .background(selectedColor.color.opacity(0.2))
                    .cornerRadius(8)

                VStack(alignment: .leading) {
                    Text(isEditing ? "Edit Connection" : "New Connection")
                        .font(.headline)
                    if !name.isEmpty {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Connection Section
                GroupBox("Connection") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledTextField(label: "Name", placeholder: "My Database", text: $name)

                        HStack(spacing: 12) {
                            LabeledTextField(label: "Host", placeholder: "localhost", text: $host)
                            LabeledTextField(label: "Port", placeholder: "5432", text: $port)
                                .frame(width: 100)
                        }

                        LabeledTextField(label: "Database", placeholder: "postgres", text: $database)
                    }
                    .padding(.vertical, 4)
                }

                // Appearance Section
                GroupBox("Appearance") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Icon")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 10), spacing: 8) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Button(action: { selectedIcon = icon }) {
                                    Image(systemName: icon)
                                        .font(.system(size: 16))
                                        .foregroundColor(selectedIcon == icon ? .white : selectedColor.color)
                                        .frame(width: 32, height: 32)
                                        .background(selectedIcon == icon ? selectedColor.color : selectedColor.color.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Color")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(IconColor.allCases, id: \.self) { color in
                                Button(action: { selectedColor = color }) {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Credentials Section
                GroupBox("Credentials") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledTextField(label: "Username", placeholder: "postgres", text: $username)
                        LabeledSecureField(label: "Password", text: $password)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()

            Spacer()

            Divider()

            // Footer
            HStack {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(!isValid || isTesting)

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connected!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button(isEditing ? "Save" : "Add") {
                    saveConnection()
                }
                .keyboardShortcut(.return)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 620)
    }

    func testConnection() {
        guard let portInt = Int(port) else { return }

        isTesting = true
        testResult = nil

        let config = ConnectionConfig(
            id: existingConnection?.id ?? UUID(),
            name: name,
            host: host,
            port: portInt,
            database: database,
            username: username,
            password: password,
            iconName: selectedIcon,
            iconColor: selectedColor
        )

        Task {
            do {
                _ = try await postgresService.connect(config: config)
                await postgresService.disconnect(configId: config.id)
                testResult = .success
                isTesting = false
            } catch {
                testResult = .failure(error.localizedDescription)
                isTesting = false
            }
        }
    }

    func saveConnection() {
        guard let portInt = Int(port) else { return }

        let config = ConnectionConfig(
            id: existingConnection?.id ?? UUID(),
            name: name,
            host: host,
            port: portInt,
            database: database,
            username: username,
            password: password,
            iconName: selectedIcon,
            iconColor: selectedColor
        )

        if isEditing {
            connectionStore.updateConnection(config)
        } else {
            connectionStore.addConnection(config)
        }

        dismiss()
    }
}

struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
        }
    }
}

struct LabeledSecureField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            SecureField("", text: $text)
        }
    }
}
