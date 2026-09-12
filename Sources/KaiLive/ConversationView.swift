import SwiftUI

struct ConversationView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            header
            meters
            transcript
            controls
            footer
        }
        .padding(16)
        .frame(width: 380, height: 500)
    }

    private var header: some View {
        HStack {
            Image(systemName: "robot")
                .font(.title2)
                .symbolEffect(.pulse, isActive: model.state == .connecting)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kai")
                    .font(.headline)
                Text(model.state.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.state == .listening || model.state == .muted {
                Text(duration(model.elapsedSeconds))
                    .monospacedDigit()
                    .font(.caption)
            }
        }
    }

    private var meters: some View {
        HStack(spacing: 12) {
            AudioMeter(label: "You", level: model.inputLevel, color: .blue)
            AudioMeter(label: "Kai", level: model.outputLevel, color: .purple)
        }
    }

    private var transcript: some View {
        Group {
            if case let .failed(message) = model.state {
                ContentUnavailableView(
                    "Kai couldn't start",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            } else if model.transcriptRows.isEmpty {
                ContentUnavailableView(
                    "Start talking",
                    systemImage: "waveform",
                    description: Text("Your conversation will appear here.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.transcriptRows) { row in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.speaker.rawValue)
                                        .font(.caption.bold())
                                        .foregroundStyle(row.speaker == .user ? .blue : .purple)
                                    Text(row.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .id(row.id)
                            }
                        }
                    }
                    .onChange(of: model.transcriptRows) {
                        if let id = model.transcriptRows.last?.id {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack {
            Button {
                Task { await model.toggleMute() }
            } label: {
                Label(
                    model.state == .muted ? "Unmute" : "Mute",
                    systemImage: model.state == .muted ? "mic" : "mic.slash"
                )
            }
            .disabled(model.state != .listening && model.state != .muted)

            Spacer()

            Button(role: .destructive) {
                Task { await model.endConversation() }
            } label: {
                Label("End", systemImage: "phone.down.fill")
            }
            .disabled(model.state == .idle || model.state == .closing)
        }
        .buttonStyle(.bordered)
    }

    private var footer: some View {
        HStack {
            Button("Settings") {
                model.openSettings()
            }
            .buttonStyle(.link)

            Spacer()

            Text("Est. \(model.estimatedCost, format: .currency(code: "USD").precision(.fractionLength(3)))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().frame(height: 14)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.link)
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct AudioMeter: View {
    let label: String
    let level: Float
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(level))
                .tint(color)
        }
    }
}
