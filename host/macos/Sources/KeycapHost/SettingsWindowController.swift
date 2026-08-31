// SPDX-License-Identifier: Apache-2.0
import AppKit
import KeycapCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: PreferencesStore) {
        let controller = NSHostingController(rootView: KeycapSettingsView(store: store))
        let window = NSWindow(contentViewController: controller)
        window.title = "Keycap Context Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 700))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct KeycapSettingsView: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        Form {
            Section("Lighting") {
                Picker("Effect", selection: mode) {
                    ForEach(LightingMode.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                HStack {
                    Text("Brightness")
                    Slider(value: brightness, in: 0...100, step: 1)
                    Text("\(store.preferences.lighting.brightness)%")
                        .monospacedDigit().frame(width: 44)
                }
                HStack {
                    Text("Speed")
                    Slider(value: speed, in: 1...100, step: 1)
                    Text("\(store.preferences.lighting.speed)%")
                        .monospacedDigit().frame(width: 44)
                }
                ForEach(0..<4, id: \.self) { index in
                    ColorPicker("Button \(index + 1)", selection: color(index), supportsOpacity: false)
                }
                Toggle(
                    "Show agent activity instead of the standby effect",
                    isOn: showAgentActivityOnKeys
                )
                if let disclosure = microphoneDisclosure {
                    Text(disclosure)
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Interaction") {
                Toggle("Hold to confirm destructive actions", isOn: holdToConfirm)
                Toggle("Show queue count", isOn: showQueueCount)
                Picker("Short press", selection: shortAction) {
                    gestureOptions
                }
                Picker("Long press", selection: longAction) {
                    gestureOptions
                }
                Picker("Double press", selection: doubleAction) {
                    gestureOptions
                }
            }

            Section("Context profiles") {
                Toggle("Enable context-aware key actions", isOn: contextProfilesEnabled)
                ForEach(store.preferences.contextProfiles.indices, id: \.self) { profileIndex in
                    profileEditor(profileIndex)
                }
                Button("Add profile") {
                    store.preferences.contextProfiles.append(ContextProfile(
                        name: "New profile",
                        applicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?
                            .bundleIdentifier ?? ""
                    ))
                }
                if let preview = previewProfile {
                    GroupBox("Current context preview · \(preview.name)") {
                        HStack {
                            ForEach(Array(preview.actions.enumerated()), id: \.element.id) { index, action in
                                VStack(alignment: .leading) {
                                    Text("KEY \(index + 1)").font(.caption2.bold())
                                    Text(action.label).lineLimit(1)
                                    Text(action.kind.displayName)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(6)
                    }
                } else {
                    Text("No profile matches the current application.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Text("Changes are saved automatically and sent to connected protocol-v2 devices.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    /// The only place a user can discover that a microphone is involved, so it
    /// states plainly what is and is not shared.
    private var microphoneDisclosure: String? {
        let shared = "Sound is analysed on the keypad and never reaches this Mac "
            + "or the network. The microphone is powered down whenever another "
            + "effect is selected. "
        switch store.preferences.lighting.mode {
        case .audio:
            return shared + "Audio Meter fills the keys with one rainbow colour as "
                + "sound gets louder; Speed sets how fast the colour cycles."
        case .spectrum:
            return shared + "Audio Spectrum gives each key its own colour and "
                + "frequency band, bass on key 1 through treble on key 4."
        case .tempo:
            return shared + "Tempo Colour fills the keys with loudness like the "
                + "meter, but steps its colour on every beat, so the palette "
                + "advances with the music instead of with a clock."
        case .pitch:
            return shared + "Pitch Colour picks one hue from what the music is "
                + "made of, red for bass through violet for treble, and "
                + "brightens with its loudness."
        default:
            return nil
        }
    }

    private var mode: Binding<LightingMode> { binding(\.lighting.mode) }
    private var showAgentActivityOnKeys: Binding<Bool> {
        binding(\.showAgentActivityOnKeys)
    }
    private var brightness: Binding<Double> {
        Binding(
            get: { Double(store.preferences.lighting.brightness) },
            set: { store.preferences.lighting.brightness = Int($0) }
        )
    }
    private var speed: Binding<Double> {
        Binding(
            get: { Double(store.preferences.lighting.speed) },
            set: { store.preferences.lighting.speed = Int($0) }
        )
    }
    private var holdToConfirm: Binding<Bool> { binding(\.interaction.holdToConfirmDestructive) }
    private var showQueueCount: Binding<Bool> { binding(\.interaction.showQueueCount) }
    private var shortAction: Binding<String> { binding(\.interaction.shortPressAction) }
    private var longAction: Binding<String> { binding(\.interaction.longPressAction) }
    private var doubleAction: Binding<String> { binding(\.interaction.doublePressAction) }
    private var contextProfilesEnabled: Binding<Bool> {
        binding(\.contextAwareProfilesEnabled)
    }

    private var previewProfile: ContextProfile? {
        guard store.preferences.contextAwareProfilesEnabled else { return nil }
        return ContextProfileMatcher.match(
            store.preferences.contextProfiles,
            applicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            project: nil
        )
    }

    @ViewBuilder private func profileEditor(_ profileIndex: Int) -> some View {
        let profile = store.preferences.contextProfiles[profileIndex]
        DisclosureGroup(profile.name.isEmpty ? "Unnamed profile" : profile.name) {
            TextField("Profile name", text: profileBinding(profileIndex, \.name))
            TextField("App bundle ID contains", text: profileBinding(
                profileIndex, \.applicationBundleIdentifier
            ))
            TextField("Project name contains", text: profileBinding(
                profileIndex, \.projectContains
            ))
            ForEach(0..<4, id: \.self) { actionIndex in
                GroupBox("Key \(actionIndex + 1)") {
                    TextField("Label", text: actionBinding(profileIndex, actionIndex, \.label))
                    Picker("Action", selection: actionBinding(profileIndex, actionIndex, \.kind)) {
                        ForEach(WorkflowActionKind.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    TextField("URL, command, or agent key", text: actionBinding(
                        profileIndex, actionIndex, \.value
                    ))
                    Toggle("Require confirmation", isOn: actionBinding(
                        profileIndex, actionIndex, \.requiresConfirmation
                    ))
                }
            }
            Button("Remove profile", role: .destructive) {
                store.preferences.contextProfiles.remove(at: profileIndex)
            }
        }
    }

    @ViewBuilder private var gestureOptions: some View {
        Text("Select key").tag("select")
        Text("Page navigation").tag("navigate")
        Text("Contextual controls").tag("contextual")
        Text("Dismiss to agent").tag("dismiss")
        Text("No action").tag("none")
    }

    private func binding<Value>(_ path: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: path] },
            set: { store.preferences[keyPath: path] = $0 }
        )
    }

    private func profileBinding<Value>(
        _ index: Int, _ path: WritableKeyPath<ContextProfile, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.preferences.contextProfiles[index][keyPath: path] },
            set: { store.preferences.contextProfiles[index][keyPath: path] = $0 }
        )
    }

    private func actionBinding<Value>(
        _ profile: Int,
        _ action: Int,
        _ path: WritableKeyPath<WorkflowAction, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.preferences.contextProfiles[profile].actions[action][keyPath: path] },
            set: { store.preferences.contextProfiles[profile].actions[action][keyPath: path] = $0 }
        )
    }

    private func color(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(hex: store.preferences.lighting.keyColors[index]) },
            set: { store.preferences.lighting.keyColors[index] = $0.hexRGB }
        )
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    var hexRGB: String {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return "000000" }
        return String(format: "%02X%02X%02X",
                      Int(color.redComponent * 255),
                      Int(color.greenComponent * 255),
                      Int(color.blueComponent * 255))
    }
}
