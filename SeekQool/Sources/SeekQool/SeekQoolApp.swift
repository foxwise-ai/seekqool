import SwiftUI
import AppKit

@main
struct SeekQoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationWillFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set as regular app so it can receive keyboard input
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.contentView = NSHostingView(rootView: contentView)
        window.title = "SeekQool"
        window.minSize = NSSize(width: 900, height: 600)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
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
