import AppKit
import SwiftUI

/// Always-on guide + live blob tuning for Feel Lab.
struct FeelGuideView: View {
    @ObservedObject private var config = FeelLabConfig.shared
    @State private var axOK = Permissions.accessibilityTrusted
    @State private var lastResult = "—"
    @State private var poll: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                instructions
                safetyBox
                resultRow
                actionsRow

                Divider().padding(.vertical, 4)

                Text("Blob studio")
                    .font(.headline)

                Text("Changes apply on the next gesture (and live while a gesture is active).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                massSection
                distributionSection
                physicsSection
                lookSection
                gooSection

                HStack {
                    Button("Reset all knobs") { config.resetToDefaults() }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(minWidth: 460, idealWidth: 480, maxWidth: 520, minHeight: 560)
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: .pluckFeelResult,
                object: nil,
                queue: .main
            ) { note in
                let s = note.object as? String
                Task { @MainActor in
                    if let s { lastResult = s }
                }
            }
            poll?.cancel()
            poll = Task { @MainActor in
                while !Task.isCancelled {
                    axOK = Permissions.accessibilityTrusted
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
        .onDisappear { poll?.cancel() }
    }

    private var header: some View {
        HStack {
            Label("Feel Lab (safe)", systemImage: "drop.fill")
                .font(.title3.weight(.semibold))
            Spacer()
            Text(axOK ? "Ready" : "Needs Accessibility")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(axOK ? Color.green.opacity(0.2) : Color.orange.opacity(0.25))
                .clipShape(Capsule())
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listen-only. Hold both buttons → stretch → release. Escape cancels.")
                .font(.callout)
                .foregroundStyle(.secondary)
            step(1, "Hold left, then right (or reverse)")
            step(2, "Blob eats the cursor — move to stretch")
            step(3, "Aim N/E/S/W · release to select")
        }
    }

    private var safetyBox: some View {
        GroupBox("Safety") {
            VStack(alignment: .leading, spacing: 4) {
                Text("• Escape cancels · auto-ends after 20s")
                Text("• Panic quit: ⌃⌥⌘P")
                Text("• Menu: Reset Pointer / Quit Pluck")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultRow: some View {
        LabeledContent("Last result") {
            Text(lastResult).font(.body.weight(.semibold))
        }
    }

    private var actionsRow: some View {
        HStack {
            Button("Reset pointer") {
                NotificationCenter.default.post(name: .pluckResetHard, object: nil)
            }
            Button("Accessibility…") {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }
            Spacer()
            Button("Quit Pluck") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Knob sections

    private var massSection: some View {
        GroupBox("Mass") {
            VStack(spacing: 10) {
                knob("Total mass (rest radius)", value: $config.restRadius, range: 24...100, format: "%.0f pt")
                knob("Stretch pull (mass from neck)", value: $config.stretchPull, range: 0...1.4, format: "%.2f")
                knob("Neck floor (min radius)", value: $config.neckFloor, range: 2...18, format: "%.0f pt")
            }
        }
    }

    private var distributionSection: some View {
        GroupBox("Distribution") {
            VStack(spacing: 10) {
                knob("Pin mass bias", value: $config.pinMass, range: 0.1...1.5, format: "%.2f")
                knob("Cursor mass bias", value: $config.headMass, range: 0.1...1.5, format: "%.2f")
                knob("Pin minimum (× rest)", value: $config.pinMinFraction, range: 0.25...1.1, format: "%.2f")
                knob("Cursor minimum (× rest)", value: $config.headMinFraction, range: 0.15...0.9, format: "%.2f")
            }
        }
    }

    private var physicsSection: some View {
        GroupBox("Physics") {
            VStack(spacing: 10) {
                knob("Responsiveness (snap)", value: $config.responsiveness, range: 0...1, format: "%.2f")
                knob("Damping (inertia)", value: $config.damping, range: 0.75...0.99, format: "%.2f")
                knob("Slosh amount", value: $config.sloshAmount, range: 0...1.5, format: "%.2f")
                knob("Whip response", value: $config.whipResponse, range: 0...1.5, format: "%.2f")
                knob("Spine particles", value: $config.particleCount, range: 6...28, format: "%.0f", step: 1)
            }
        }
    }

    private var lookSection: some View {
        GroupBox("Optics (obsidian glass)") {
            VStack(spacing: 10) {
                knob("Shininess / clearcoat", value: $config.shininess, range: 0...1.5, format: "%.2f")
                knob("Fresnel rim", value: $config.fresnel, range: 0...1.5, format: "%.2f")
                knob("Transmission (light through)", value: $config.transmission, range: 0...1.2, format: "%.2f")
                knob("Absorption (Beer depth)", value: $config.absorption, range: 0...1.5, format: "%.2f")
                knob("Glass opacity", value: $config.glassOpacity, range: 0.4...1, format: "%.2f")
                knob("Contact shadow", value: $config.shadowStrength, range: 0...1, format: "%.2f")
                knob("Base lightness", value: $config.lightness, range: 0.02...0.25, format: "%.2f")
                knob("Cool tint (monitor glow)", value: $config.coolTint, range: 0...1, format: "%.2f")
            }
        }
    }

    private var gooSection: some View {
        GroupBox("Metaball field") {
            VStack(spacing: 10) {
                Text("Iso threshold controls how soft the liquid merge is (SDF field).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                knob("Field merge / threshold", value: $config.gooThreshold, range: 0.2...0.85, format: "%.2f")
            }
        }
    }

    private func knob(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        step: Double? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            Text(text).font(.callout)
        }
    }
}

extension Notification.Name {
    static let pluckFeelResult = Notification.Name("pluck.feelResult")
    static let pluckResetHard = Notification.Name("pluck.resetHard")
}

@MainActor
final class FeelGuideController {
    static let shared = FeelGuideController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: FeelGuideView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "Pluck · Feel Lab (safe)"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 500, height: 720))
            w.minSize = NSSize(width: 440, height: 400)
            w.level = .floating
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
