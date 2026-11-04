import SwiftUI

struct EditorView: View {
    @ObservedObject var state: PrompterState
    var onSnap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Script").font(.headline)
                TextEditor(text: $state.script)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                let minutes = Double(state.wordCount) / 140.0
                Text("\(state.wordCount) words · about \(String(format: "%.1f", minutes)) min at a natural pace")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)

            Divider()

            Form {
                Section("Playback") {
                    HStack {
                        Button(state.isPlaying ? "Pause" : "Play") { state.togglePlay() }
                        Button("Restart") { state.restart() }
                    }
                    labeledSlider("Speed", value: $state.speed, range: 5...300, format: "%.0f pt/s")
                }
                Section("Appearance") {
                    labeledSlider("Text size", value: $state.fontSize, range: 12...56, format: "%.0f pt")
                    Picker("Font", selection: $state.fontDesign) {
                        Text("Rounded").tag("rounded")
                        Text("System").tag("default")
                        Text("Mono").tag("monospaced")
                        Text("Serif").tag("serif")
                    }
                    labeledSlider("Width", value: $state.panelWidth, range: 240...1200, format: "%.0f")
                    labeledSlider("Height", value: $state.panelHeight, range: 90...600, format: "%.0f")
                    Button("Snap back under the notch", action: onSnap)
                }
                Section("Voice mode") {
                    Toggle("Pause when I stop talking", isOn: $state.voiceMode)
                    if state.voiceMode {
                        ProgressView(value: Double(min(max((state.micLevel + 80) / 80, 0), 1)))
                        labeledSlider("Sensitivity threshold", value: $state.voiceThreshold, range: -70...(-10), format: "%.0f dB")
                        Text(state.isSpeaking ? "🟢 Hearing you" : "⚪️ Silence")
                            .font(.caption)
                    }
                }
                Section("Shortcuts (work in any app)") {
                    shortcut("⌃⌥Space", "Play / pause")
                    shortcut("⌃⌥↑ / ↓", "Faster / slower")
                    shortcut("⌃⌥←", "Jump back")
                    shortcut("⌃⌥R", "Restart")
                    shortcut("⌃⌥M", "Voice mode on/off")
                    shortcut("⌃⌥H", "Hide / show prompter")
                    shortcut("⌃⌥E", "Open this editor")
                }
            }
            .formStyle(.grouped)
            .frame(width: 320)
        }
        .frame(minWidth: 780, minHeight: 540)
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).foregroundColor(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(keys).font(.system(.body, design: .monospaced))
            Spacer()
            Text(label).foregroundColor(.secondary)
        }
    }
}
