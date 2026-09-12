import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var apiKey = ""

    private let voices = [
        "meridian", "gleam", "quartz", "ripple", "vesper", "willow",
        "stone", "bossa", "tempo", "beacon", "delta", "cinder"
    ]

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField(model.hasAPIKey() ? "Saved in Keychain" : "API key", text: $apiKey)
                HStack {
                    Button("Save API Key") {
                        model.saveAPIKey(apiKey)
                        apiKey = ""
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Remove", role: .destructive) {
                        model.deleteAPIKey()
                    }
                    .disabled(!model.hasAPIKey())
                }
                Text("The key is stored in macOS Keychain, not app preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice") {
                Picker("Kai's voice", selection: Bindable(model).selectedVoice) {
                    ForEach(voices, id: \.self) { voice in
                        Text(voice.capitalized).tag(voice)
                    }
                }
            }

            Section("Personality") {
                TextEditor(text: Bindable(model).instructions)
                    .frame(minHeight: 100)
                Text("Keep instructions short. GPT-Live handles pacing, tone, and interruptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = model.settingsMessage {
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
