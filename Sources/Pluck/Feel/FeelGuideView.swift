import AppKit
import PluckCore
import SwiftUI

/// Always-on guide + live blob tuning for Feel Lab.
struct FeelGuideView: View {
    @ObservedObject private var config = FeelLabConfig.shared
    @State private var axOK = Permissions.accessibilityTrusted
    @State private var lastResult = "—"
    @State private var poll: Task<Void, Never>?
    @State private var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "feelLab.tab") ?? "") ?? .looks
    @State private var styleFilter: String = "all"

    enum Tab: String, CaseIterable, Identifiable {
        case looks, feel, trigger, advanced, help
        var id: String { rawValue }
        var title: String {
            switch self {
            case .looks: return "Looks"
            case .feel: return "Feel"
            case .trigger: return "Trigger"
            case .advanced: return "Advanced"
            case .help: return "Help"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: tab) { _, new in UserDefaults.standard.set(new.rawValue, forKey: "feelLab.tab") }
            }
            .padding([.horizontal, .top], 18)
            .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .looks: looksTab
                    case .feel: feelTab
                    case .trigger: triggerTab
                    case .advanced: advancedTab
                    case .help: helpTab
                    }
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 560, minHeight: 560)
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

    // MARK: - Tabs

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Last: \(lastResult)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Reset pointer") { NotificationCenter.default.post(name: .pluckResetHard, object: nil) }
                .controlSize(.small)
                .help("If the cursor ever looks stuck or hidden")
            Text("Esc cancels · ⌃⌥⌘P quits").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func sectionTitle(_ text: String, _ sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.headline)
            if let sub { hint(sub) }
        }
    }

    private static let styleIcons: [String: String] = [
        "liquid": "drop.fill", "ferro": "bolt.fill", "crystal": "diamond.fill", "gravity": "moon.stars.fill",
        "pearls": "circle.grid.3x3.fill", "swarm": "sparkles", "tendrils": "leaf.fill", "jumprope": "figure.jumprope",
        "stars": "star.fill", "kite": "wind", "bubbles": "bubbles.and.sparkles.fill", "beam": "bolt.horizontal.fill", "lightning": "bolt.fill", "magnet": "magnet", "slinky": "waveform.path", "tincan": "phone.bubble.fill", "thread": "heart.fill", "pingpong": "tennisball.fill", "bridge": "figure.walk", "planes": "paperplane.fill", "water": "drop.fill",
        "train": "tram.fill", "equalizer": "waveform", "dna": "link", "fishing": "fish.fill", "ribbon": "scribble.variable",
    ]

    private var looksTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Style", "How it moves and what it's made of. Pick one, then a preset or colours below.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(AnimationStyle.allCases, id: \.rawValue) { st in styleCard(st) }
            }

            sectionTitle("Presets", "A style, its physics and its colours together.")
            Picker("", selection: $styleFilter) {
                Text("All").tag("all")
                ForEach(AnimationStyle.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 200, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(PresetLibrary.everything.filter { styleFilter == "all" || $0.style.rawValue == styleFilter }) { p in presetCard(p) }
            }

            sectionTitle("Colours", "Keep the current feel and change only the look.")
            themeStrip
        }
    }

    private func styleCard(_ st: AnimationStyle) -> some View {
        let selected = config.styleID == st.rawValue
        return Button { config.styleID = st.rawValue } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: Self.styleIcons[st.rawValue] ?? "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.name).font(.caption.weight(.semibold))
                    Text(st.tagline).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var themeStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ThemeLibrary.all) { t in themeChip(t) }
                    if let custom = config.customTheme { themeChip(custom) }
                    Button { config.surpriseMe() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "dice")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.accentColor.opacity(0.18)))
                            Text("Surprise").font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("A random harmonious palette")
                }
                .padding(.vertical, 2)
            }
            hint("Now: \(config.theme.name)")
        }
    }

    private var feelTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("How it feels", "The few controls that matter most. Changes show on the next pull.")
            simpleKnob("Size", "How big the blob is at rest.", value: $config.restRadius, range: 24...110, format: "%.0f")
            simpleKnob("Stretchiness", "How much material the thread draws out of the ends as you pull.", value: $config.stretchPull, range: 0...1.4, format: "%.2f")
            simpleKnob("Follow speed", "How quickly the blob chases your cursor. Higher is snappier.", value: $config.magnetPull, range: 25...120, format: "%.0f")
            simpleKnob("Weight", "Heavy and slow to settle, or light and quick.", value: $config.magnetWeight, range: 0.3...1.1, format: "%.2f")
            simpleKnob("Reach", "How far a small hand movement stretches it across the screen.", value: $config.reachGain, range: 0...4, format: "%.1f")
            simpleKnob("Bounce on release", "The wobble when it snaps back.", value: $config.recoilBounce, range: 0...1, format: "%.2f")
            simpleKnob("Gravity", "How much it sags and pools downward.", value: $config.gravity, range: 0...1.5, format: "%.2f")
            simpleKnob("Aliveness", "How much it breathes and drifts when you hold still.", value: $config.idleLife, range: 0...1.5, format: "%.2f")
            simpleKnob("Flick momentum", "How far it overshoots when you flick and let go.", value: $config.flingMomentum, range: 0...1.2, format: "%.2f")
            Divider()
            Toggle("Meeting mode (smaller and quieter)", isOn: $config.meetingMode)
            Toggle("Trackpad haptic ticks", isOn: $config.hapticsEnabled)
            Toggle("Soft sounds", isOn: $config.soundEnabled)
            HStack {
                Spacer()
                Button("Reset all to defaults") { config.resetToDefaults() }
                    .controlSize(.small)
            }
        }
        .font(.callout)
    }

    private func simpleKnob(_ title: String, _ blurb: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            Text(blurb).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var triggerTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("How you start it", "Pluck only listens. It never clicks or types for you. Pick whichever suits your hands.")
            triggerSection
        }
    }

    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            hint("Fine controls for tuning by hand. Most people never need these.")
            DisclosureGroup("Mass distribution") { VStack(spacing: 10) { massSection; distributionSection }.padding(.top, 6) }
            DisclosureGroup("Physics") { physicsSection.padding(.top, 6) }
            DisclosureGroup("Optics (glass)") { lookSection.padding(.top, 6) }
            DisclosureGroup("Metaball field") { gooSection.padding(.top, 6) }
            DisclosureGroup("Fidget extras") { fidgetSection.padding(.top, 6) }
        }
    }

    private var helpTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("How it works")
            instructions
            safetyBox
            actionsRow
        }
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
            Text("Listen-only: nothing is ever clicked or typed for you.")
                .font(.callout)
                .foregroundStyle(.secondary)
            step(1, "Start it: hold ⌥ or Hyper, rest three fingers, or hold both mouse buttons (see Trigger)")
            step(2, "Move: the blob stretches from where you started and follows your cursor anywhere on screen")
            step(3, "Aim toward a direction to arm its action, then release to choose it. Esc cancels")
        }
    }

    private var safetyBox: some View {
        GroupBox("Safety") {
            VStack(alignment: .leading, spacing: 4) {
                Text("• Escape cancels · auto-ends after 12s idle")
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

    private var triggerSection: some View {
        GroupBox("Trackpad triggers") {
            VStack(alignment: .leading, spacing: 10) {
                Text("The two-mouse-button chord always works. Without a second button, use one of these:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("No-click trigger", selection: $config.modifierTriggerRaw) {
                    Text("Off").tag(0)
                    Text("Hold ⌥").tag(1)
                    Text("Hold Hyper ⌃⌥⇧⌘").tag(2)
                }
                .pickerStyle(.segmented)
                knob("Hold time before it arms", value: $config.modifierHoldMs, range: 100...600, format: "%.0f ms")
                Text("Hold the modifier (⌥ also needs the pointer held still), then move to stretch. Release the modifier to commit; Esc cancels. No click, so nothing reaches the app underneath.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("Modifier + press-and-hold, then drag (clicks)", isOn: $config.trackpadTriggerEnabled)
                    .font(.caption)
                Picker("Modifier", selection: $config.trackpadModifierRaw) {
                    ForEach(TriggerModifier.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(!config.trackpadTriggerEnabled)
                knob("Press-and-hold time", value: $config.trackpadHoldMs, range: 120...500, format: "%.0f ms")
                Text("Pluck only listens, so the click/drag also reaches the app underneath (⌥ is the least intrusive).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Three fingers rest, then drag (experimental, private API)", isOn: $config.threeFingerEnabled)
                    .font(.caption)
                knob("Rest time before it arms", value: $config.threeFingerHoldMs, range: 100...500, format: "%.0f ms")
                    .disabled(!config.threeFingerEnabled)
                Text("Rest three fingers on the pad without moving, then drag; lift to commit. If you start moving right away it stays a normal three-finger drag. The system three-finger drag still reaches the app underneath (Pluck only listens), so it's cleanest with that turned off.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Best with System Settings ▸ Accessibility ▸ Pointer Control ▸ Trackpad Options ▸ Dragging style: Three Finger Drag, and the three-finger Mission Control / Spaces swipes turned off.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Looks & feels

    private func swatch(_ t: LiquidTheme) -> LinearGradient {
        func c(_ x: RGB) -> Color { Color(red: Double(min(1, x.r)), green: Double(min(1, x.g)), blue: Double(min(1, x.b))) }
        return LinearGradient(colors: [c(t.a), c(t.b), c(t.c)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var looksSection: some View {
        GroupBox("Looks & feels") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Animation style")
                    .font(.caption.weight(.semibold))
                Picker("Animation style", selection: $config.styleID) {
                    ForEach(AnimationStyle.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(config.style.tagline).font(.caption2).foregroundStyle(.secondary)

                Text("Feel presets: style, physics and colours together")
                    .font(.caption.weight(.semibold))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(PresetLibrary.everything) { p in presetCard(p) }
                }

                Text("Colour themes: keep the current feel, change the look")
                    .font(.caption.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ThemeLibrary.all) { t in themeChip(t) }
                        if let custom = config.customTheme { themeChip(custom) }
                        Button { config.surpriseMe() } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "dice")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.accentColor.opacity(0.18)))
                                Text("Surprise").font(.system(size: 9))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("A random harmonious palette")
                    }
                    .padding(.vertical, 2)
                }
                Text("Now: \(config.theme.name)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func presetCard(_ p: FeelPreset) -> some View {
        let theme = ThemeLibrary.theme(id: p.themeID) ?? ThemeLibrary.obsidianEmber
        let selected = config.presetID == p.id
        return Button { config.apply(preset: p) } label: {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(swatch(theme))
                    .frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)).padding(.trailing, 28))
                HStack(spacing: 5) {
                    Text(p.name).font(.caption.weight(.semibold))
                    if p.style != .liquid {
                        Text(p.style.name).font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                    }
                }
                Text(p.tagline).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func themeChip(_ t: LiquidTheme) -> some View {
        let selected = config.themeID == t.id
        return Button { config.apply(theme: t) } label: {
            VStack(spacing: 3) {
                Circle().fill(swatch(t)).frame(width: 36, height: 36)
                    .overlay(Circle().stroke(selected ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: selected ? 2.5 : 1))
                Text(t.name).font(.system(size: 9)).lineLimit(1).frame(width: 58)
            }
        }
        .buttonStyle(.plain)
        .help(t.tagline)
    }

    private var fidgetSection: some View {
        GroupBox("Fidget feel") {
            VStack(spacing: 10) {
                knob("Release bounce (snap-back wobble)", value: $config.recoilBounce, range: 0...1, format: "%.2f")
                knob("Crystallize with stretch", value: $config.crystallize, range: 0...1, format: "%.2f")
                knob("Idle breathing", value: $config.idleLife, range: 0...1.5, format: "%.2f")
                knob("Reach gain (small motion → far stretch)", value: $config.reachGain, range: 0...4, format: "%.2f")
                knob("Gravity (sag + pooling)", value: $config.gravity, range: 0...1.5, format: "%.2f")
                knob("Magnet pull (head follow)", value: $config.magnetPull, range: 25...120, format: "%.0f rad/s")
                knob("Magnet weight (damping)", value: $config.magnetWeight, range: 0.3...1.1, format: "%.2f")
                knob("Magnet stick (snap when close)", value: $config.magnetStick, range: 0...1.8, format: "%.2f")
                knob("Fling momentum (overshoot on flick)", value: $config.flingMomentum, range: 0...1.2, format: "%.2f")
                Toggle("Meeting mode (smaller, dimmer)", isOn: $config.meetingMode)
                    .font(.caption)
                Toggle("Trackpad haptic ticks (direction + stretch detents)", isOn: $config.hapticsEnabled)
                    .font(.caption)
                Toggle("Soft sounds (quiet tick on latch, plip on commit)", isOn: $config.soundEnabled)
                    .font(.caption)
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
                knob("Glow intensity (× theme)", value: $config.ember, range: 0...1.6, format: "%.2f")
                Toggle("Obsidian facets (off while we tune the liquid)", isOn: $config.facetsEnabled)
                    .font(.caption)
                knob("Facets (liquid → obsidian)", value: $config.facetAmount, range: 0...1, format: "%.2f")
                    .disabled(!config.facetsEnabled)
                knob("Facet size", value: $config.facetSize, range: 8...50, format: "%.0f pt")
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
