import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var version: String = ""
    @State private var build: String = ""

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            widgets
                .tabItem { Label("Widgets", systemImage: "rectangle.grid.2x2") }
            calendar
                .tabItem { Label("Calendar", systemImage: "calendar") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 420)
        .onAppear {
            let info = Bundle.main.infoDictionary
            version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
            build = info?["CFBundleVersion"] as? String ?? "1"
        }
    }

    private var general: some View {
        Form {
            Section("Interaction") {
                Toggle("Open on hover", isOn: $settings.openOnHover)
                VStack(alignment: .leading) {
                    Text("Hover intent delay: \(Int(round(settings.hoverIntentDelay * 1000))) ms")
                    Slider(value: hoverDelayMS, in: 0...200, step: 10)
                }
                VStack(alignment: .leading) {
                    Text("Close delay: \(Int(round(settings.closeDelay * 1000))) ms")
                    Slider(value: closeDelayMS, in: 0...300, step: 10)
                }
                Toggle("Vertical gestures", isOn: $settings.verticalGesturesEnabled)
            }
            Section("Haptics") {
                Toggle("Haptics enabled", isOn: $settings.hapticsEnabled)
                Picker("Haptic pattern", selection: $settings.hapticPattern) {
                    Text("Generic").tag("generic")
                    Text("Alignment").tag("alignment")
                    Text("Level Change").tag("levelChange")
                }
                .disabled(!settings.hapticsEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var widgets: some View {
        Form {
            Section("Widgets") {
                Toggle("Media widget", isOn: $settings.mediaWidgetEnabled)
                Toggle("Calendar widget", isOn: $settings.calendarWidgetEnabled)
                Toggle("Compact live activity", isOn: $settings.mediaCompactEnabled)
                Toggle("Show Dynamic Island style (Macs without a notch)", isOn: $settings.showDynamicIslandStyle)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var calendar: some View {
        Form {
            Section("Calendar access") {
                Text("Change calendar access in System Settings.")
                Button("Open System Settings") {
                    CalendarSettingsLink.open()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var about: some View {
        Form {
            Section("About") {
                Text("BilouNook")
                Text("Version: \(version)")
                Text("Build: \(build)")
                Button("Reset all settings") {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hoverDelayMS: Binding<Double> {
        Binding(
            get: { settings.hoverIntentDelay * 1000 },
            set: { settings.hoverIntentDelay = $0 / 1000 }
        )
    }

    private var closeDelayMS: Binding<Double> {
        Binding(
            get: { settings.closeDelay * 1000 },
            set: { settings.closeDelay = $0 / 1000 }
        )
    }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView()
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 480, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Settings"
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
