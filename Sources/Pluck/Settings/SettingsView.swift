import AppKit
import PluckCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var excludes = ExcludeList.shared
    @State private var axOK = false
    @State private var imOK = false
    @State private var newBundleID = ""
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        TabView {
            permissionsTab.tabItem { Label("Permissions", systemImage: "lock.shield") }
            excludesTab.tabItem { Label("Excludes", systemImage: "app.badge") }
            aboutTab.tabItem { Label("About", systemImage: "drop.fill") }
        }
        .frame(width: 440, height: 380)
        .onAppear {
            refresh()
            pollTask?.cancel()
            pollTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    refresh()
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var permissionsTab: some View {
        Form {
            Section {
                Text("Use Set Up Permissions from the menu bar for the guided flow. Status here updates live.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Status") {
                LabeledContent("Accessibility") {
                    Text(axOK ? "On" : "Off").foregroundStyle(axOK ? .green : .orange)
                }
                Text("Feel Lab is listen-only. Input Monitoring automation was removed after it could lock input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Set Up Accessibility…") {
                    SetupWindowController.shared.show {}
                }
            }
            Section("This build") {
                Text(Permissions.appPath)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var excludesTab: some View {
        Form {
            Section("Excluded apps") {
                ForEach(excludes.bundleIDs.sorted(), id: \.self) { id in
                    HStack {
                        Text(id).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) { excludes.remove(id) } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("com.example.app", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let t = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        excludes.add(t)
                        newBundleID = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pluck", systemImage: "drop.fill").font(.title2.weight(.semibold))
            Text("Hold one button, press the other, stretch, release. Quit from the menu bar if anything feels stuck.")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Version 0.1.0").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func refresh() {
        axOK = Permissions.accessibilityTrusted
        imOK = Permissions.inputMonitoringTrusted
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Pluck"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 460, height: 400))
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
