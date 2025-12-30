import AppKit
import SwiftUI

class ConnectionWindowController {
    static let shared = ConnectionWindowController()
    private var windowController: NSWindowController?

    func showConnectionForm(
        connectionStore: ConnectionStore,
        postgresService: PostgresService,
        existingConnection: ConnectionConfig? = nil
    ) {
        windowController?.close()

        let formView = ConnectionFormView(
            connectionStore: connectionStore,
            postgresService: postgresService,
            existingConnection: existingConnection,
            onDismiss: { [weak self] in
                self?.windowController?.close()
                self?.windowController = nil
            }
        )

        let hostingView = NSHostingView(rootView: formView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = existingConnection == nil ? "New Connection" : "Edit Connection"
        window.center()

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        windowController?.close()
        windowController = nil
    }
}

// MARK: - SwiftUI Connection Form

struct ConnectionFormView: View {
    let connectionStore: ConnectionStore
    let postgresService: PostgresService
    let existingConnection: ConnectionConfig?
    let onDismiss: () -> Void

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

    init(connectionStore: ConnectionStore, postgresService: PostgresService, existingConnection: ConnectionConfig?, onDismiss: @escaping () -> Void) {
        self.connectionStore = connectionStore
        self.postgresService = postgresService
        self.existingConnection = existingConnection
        self.onDismiss = onDismiss

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

    var isEditing: Bool { existingConnection != nil }

    var isValid: Bool {
        !name.isEmpty && !host.isEmpty && !database.isEmpty && !username.isEmpty && (Int(port) != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionSection
                    appearanceSection
                    credentialsSection
                }
                .padding(24)
            }

            Divider()
            footer
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedIcon)
                .font(.system(size: 28))
                .foregroundColor(selectedColor.color)
                .frame(width: 48, height: 48)
                .background(selectedColor.color.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "Edit Connection" : "New Connection")
                    .font(.title3)
                    .fontWeight(.semibold)
                if !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
    }

    var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connection", systemImage: "network")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 12) {
                FormField(label: "Name", placeholder: "My Database", text: $name)

                HStack(spacing: 12) {
                    FormField(label: "Host", placeholder: "localhost", text: $host)
                    FormField(label: "Port", placeholder: "5432", text: $port)
                        .frame(width: 90)
                }

                FormField(label: "Database", placeholder: "postgres", text: $database)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Appearance", systemImage: "paintpalette")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 10), spacing: 8) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Button(action: { selectedIcon = icon }) {
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(selectedIcon == icon ? .white : selectedColor.color)
                                    .frame(width: 36, height: 36)
                                    .background(selectedIcon == icon ? selectedColor.color : selectedColor.color.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        ForEach(IconColor.allCases, id: \.self) { color in
                            Button(action: { selectedColor = color }) {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .shadow(color: selectedColor == color ? color.color.opacity(0.5) : .clear, radius: 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Credentials", systemImage: "key")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 12) {
                FormField(label: "Username", placeholder: "postgres", text: $username)
                FormField(label: "Password", placeholder: "", text: $password, isSecure: true)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    var footer: some View {
        HStack(spacing: 12) {
            Button(action: testConnection) {
                HStack(spacing: 6) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "bolt")
                    }
                    Text("Test")
                }
            }
            .disabled(!isValid || isTesting)

            if let result = testResult {
                let isSuccess = { () -> Bool in
                    if case .success = result { return true }
                    return false
                }()
                HStack(spacing: 4) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(isSuccess ? "Connected!" : "Failed")
                }
                .font(.caption)
                .foregroundColor(isSuccess ? .green : .red)
            }

            Spacer()

            Button("Cancel") { onDismiss() }
                .keyboardShortcut(.escape)

            Button(isEditing ? "Save" : "Add Connection") { saveConnection() }
                .keyboardShortcut(.return)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    func testConnection() {
        guard let portInt = Int(port) else { return }
        isTesting = true
        testResult = nil

        let config = ConnectionConfig(
            id: existingConnection?.id ?? UUID(),
            name: name, host: host, port: portInt, database: database,
            username: username, password: password,
            iconName: selectedIcon, iconColor: selectedColor
        )

        Task {
            do {
                _ = try await postgresService.connect(config: config)
                await postgresService.disconnect(configId: config.id)
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    func saveConnection() {
        guard let portInt = Int(port) else { return }

        let config = ConnectionConfig(
            id: existingConnection?.id ?? UUID(),
            name: name, host: host, port: portInt, database: database,
            username: username, password: password,
            iconName: selectedIcon, iconColor: selectedColor
        )

        if isEditing {
            connectionStore.updateConnection(config)
        } else {
            connectionStore.addConnection(config)
        }
        onDismiss()
    }
}

// MARK: - Form Field Component

struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
