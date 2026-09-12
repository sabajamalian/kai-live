import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case idle
        case connecting
        case listening
        case muted
        case closing
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Ready"
            case .connecting: "Connecting"
            case .listening: "Listening"
            case .muted: "Muted"
            case .closing: "Ending"
            case .failed: "Needs attention"
            }
        }
    }

    var state: State = .idle
    var transcriptRows: [TranscriptRow] = []
    var inputLevel: Float = 0
    var outputLevel: Float = 0
    var elapsedSeconds: TimeInterval = 0
    var finalUsageSeconds: TimeInterval?
    var usageConfirmed = false
    var settingsMessage: String?
    var openSettingsHandler: (() -> Void)?

    var selectedVoice: String {
        get { UserDefaults.standard.string(forKey: "selectedVoice") ?? "meridian" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedVoice") }
    }

    var instructions: String {
        get {
            UserDefaults.standard.string(forKey: "instructions")
                ?? "You are Kai, a calm and friendly voice companion. Speak naturally and concisely. Stop speaking when interrupted and listen carefully."
        }
        set { UserDefaults.standard.set(newValue, forKey: "instructions") }
    }

    private let keychain: KeychainStoring
    private var session: LiveSession?
    private var timerTask: Task<Void, Never>?
    private var sessionStartedAt: ContinuousClock.Instant?

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
    }

    var estimatedCost: Decimal {
        Decimal(elapsedSeconds / 60) * Decimal(string: "0.05")!
    }

    func hasAPIKey() -> Bool {
        (try? keychain.readAPIKey())?.isEmpty == false
    }

    func saveAPIKey(_ key: String) {
        do {
            try keychain.saveAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
            settingsMessage = "API key saved securely in Keychain."
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func deleteAPIKey() {
        do {
            try keychain.deleteAPIKey()
            settingsMessage = "API key removed."
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    func startConversation() async {
        guard state == .idle || isFailure else { return }
        guard let apiKey = try? keychain.readAPIKey(), !apiKey.isEmpty else {
            state = .failed("Add your OpenAI API key in Settings.")
            return
        }

        state = .connecting
        transcriptRows.removeAll()
        elapsedSeconds = 0
        finalUsageSeconds = nil
        usageConfirmed = false

        let session = LiveSession(
            apiKey: apiKey,
            voice: selectedVoice,
            instructions: instructions,
            onEvent: { [weak self] event in
                self?.handle(event)
            },
            onInputLevel: { [weak self] level in
                self?.inputLevel = level
            },
            onOutputLevel: { [weak self] level in
                self?.outputLevel = level
            }
        )
        self.session = session

        do {
            try await session.start()
        } catch {
            self.session = nil
            state = .failed(error.localizedDescription)
        }
    }

    func toggleMute() async {
        guard let session else { return }
        do {
            switch state {
            case .listening:
                try await session.setMuted(true)
            case .muted:
                try await session.setMuted(false)
            default:
                break
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func endConversation() async {
        guard let session, state != .closing else {
            if session == nil, !isFailure { state = .idle }
            return
        }

        state = .closing
        timerTask?.cancel()
        timerTask = nil

        do {
            try await session.close()
        } catch {
            state = .failed(error.localizedDescription)
        }

        self.session = nil
        transcriptRows.removeAll()
        inputLevel = 0
        outputLevel = 0
        if !isFailure { state = .idle }
    }

    func stopImmediately() {
        timerTask?.cancel()
        session?.stopImmediately()
    }

    func openSettings() {
        openSettingsHandler?()
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private func handle(_ event: LiveSession.Event) {
        switch event {
        case .started:
            state = .listening
            sessionStartedAt = .now
            startTimer()
        case let .transcript(speaker, delta, startMilliseconds, endMilliseconds):
            appendTranscript(
                speaker: speaker,
                delta: delta,
                startMilliseconds: startMilliseconds,
                endMilliseconds: endMilliseconds
            )
        case let .muted(isMuted):
            state = isMuted ? .muted : .listening
        case let .closed(durationSeconds):
            usageConfirmed = true
            finalUsageSeconds = durationSeconds
        case let .error(message):
            timerTask?.cancel()
            state = .failed(message)
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let startedAt = self.sessionStartedAt else { return }
                self.elapsedSeconds = startedAt.duration(to: .now).seconds
            }
        }
    }

    private func appendTranscript(
        speaker: TranscriptRow.Speaker,
        delta: String,
        startMilliseconds: Int,
        endMilliseconds: Int
    ) {
        let gapThreshold = 1_200
        if let index = transcriptRows.lastIndex(where: {
            $0.speaker == speaker && startMilliseconds - $0.endMilliseconds < gapThreshold
        }) {
            transcriptRows[index].text += delta
            transcriptRows[index].endMilliseconds = max(endMilliseconds, transcriptRows[index].endMilliseconds)
        } else {
            transcriptRows.append(
                TranscriptRow(
                    speaker: speaker,
                    text: delta,
                    startMilliseconds: startMilliseconds,
                    endMilliseconds: endMilliseconds
                )
            )
        }
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
