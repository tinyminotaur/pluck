import AppKit
import SwiftUI

/// Single place for the Accessibility permission (the only one Pluck needs).
struct SetupView: View {
    var onReady: () -> Void

    @State private var axOK = false
    @State private var poll: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Set up Pluck", systemImage: "drop.fill")
                .font(.title2.weight(.semibold))

            Text("Pluck needs one permission: Accessibility, so it can notice your trigger and draw over other apps. It only listens, and never blocks or sends mouse or keyboard input.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: axOK ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(axOK ? .green : .secondary)
                    Text("Accessibility").font(.headline)
                    Spacer()
                    Text(axOK ? "On" : "Off").foregroundStyle(.secondary)
                }
                Text("macOS shows this under System Settings > Privacy & Security > Accessibility.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !axOK {
                    Button("Enable Accessibility") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                        refresh()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                Button("Get started") { onReady() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!axOK)
            }
        }
        .padding(28)
        .frame(width: 440)
        .onAppear {
            refresh()
            poll?.cancel()
            poll = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    refresh()
                }
            }
        }
        .onDisappear {
            poll?.cancel()
            poll = nil
        }
    }

    private func refresh() {
        axOK = Permissions.accessibilityTrusted
    }
}

@MainActor
final class SetupWindowController {
    static let shared = SetupWindowController()
    private var window: NSWindow?

    func show(onReady: @escaping () -> Void) {
        let hosting = NSHostingController(rootView: SetupView(onReady: { [weak self] in
            UserDefaults.standard.set(true, forKey: "pluck.didOnboard")
            self?.window?.close()
            self?.window = nil
            onReady()
        }))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Pluck"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 320))
        window.center()
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
