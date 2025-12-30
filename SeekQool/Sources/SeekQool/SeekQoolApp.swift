import SwiftUI
import AppKit

@main
struct SeekQoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Query Tab") {
                    NotificationCenter.default.post(name: .newQueryTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeCurrentTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Database") {
                Button("New Connection...") {
                    NotificationCenter.default.post(name: .newConnection, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshCurrentTab, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app activates properly
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Reopen window if all windows were closed
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Make sure main window comes to front
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

extension Notification.Name {
    static let newQueryTab = Notification.Name("newQueryTab")
    static let closeCurrentTab = Notification.Name("closeCurrentTab")
    static let newConnection = Notification.Name("newConnection")
    static let refreshCurrentTab = Notification.Name("refreshCurrentTab")
}

struct SettingsView: View {
    @AppStorage("defaultPageSize") private var defaultPageSize = 100
    @AppStorage("confirmBeforePush") private var confirmBeforePush = true

    var body: some View {
        Form {
            Section("Data Display") {
                Picker("Default Page Size", selection: $defaultPageSize) {
                    Text("50 rows").tag(50)
                    Text("100 rows").tag(100)
                    Text("250 rows").tag(250)
                    Text("500 rows").tag(500)
                    Text("1000 rows").tag(1000)
                }
            }

            Section("Safety") {
                Toggle("Always preview SQL before pushing changes", isOn: $confirmBeforePush)
            }
        }
        .padding()
        .frame(width: 450, height: 200)
    }
}
