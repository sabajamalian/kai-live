import Foundation

actor LiveSession {
    enum Event: Sendable {
        case started
        case transcript(
            speaker: TranscriptRow.Speaker,
            delta: String,
            startMilliseconds: Int,
            endMilliseconds: Int
        )
        case muted(Bool)
        case closed(durationSeconds: TimeInterval?)
        case error(String)
    }

    typealias EventHandler = @MainActor @Sendable (Event) async -> Void
    typealias LevelHandler = @MainActor @Sendable (Float) -> Void

    private let apiKey: String
    private let voice: String
    private let instructions: String
    private let onEvent: EventHandler
    private let onInputLevel: LevelHandler
    private let onOutputLevel: LevelHandler
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var audio: AudioPipeline?
    private var started = false
    private var closing = false
    private var closeReceived = false
    private var closeContinuation: CheckedContinuation<Void, Error>?
    private var closeTimeoutTask: Task<Void, Never>?

    init(
        apiKey: String,
        voice: String,
        instructions: String,
        onEvent: @escaping EventHandler,
        onInputLevel: @escaping LevelHandler,
        onOutputLevel: @escaping LevelHandler
    ) {
        self.apiKey = apiKey
        self.voice = voice
        self.instructions = instructions
        self.onEvent = onEvent
        self.onInputLevel = onInputLevel
        self.onOutputLevel = onOutputLevel
    }

    func start() async throws {
        guard webSocket == nil else { return }

        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/live/sessions")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let socket = URLSession.shared.webSocketTask(with: request)
        webSocket = socket
        socket.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
        try await send(ClientEvent.sessionStart(voice: voice, instructions: instructions))
    }

    func setMuted(_ muted: Bool) async throws {
        guard started, !closing else { return }
        try await send(ClientEvent.mute(muted, eventID: UUID().uuidString))
    }

    func close() async throws {
        guard let webSocket else { return }
        guard started else {
            stopImmediately()
            return
        }
        guard !closing else { return }

        closing = true
        audio?.stop()
        do {
            try await send(ClientEvent.close())
            try await waitForClose()
        } catch {
            stopNow()
            throw error
        }

        webSocket.cancel(with: .normalClosure, reason: nil)
        receiveTask?.cancel()
        self.webSocket = nil
    }

    nonisolated func stopImmediately() {
        Task { await stopNow() }
    }

    private func stopNow() {
        closeTimeoutTask?.cancel()
        audio?.stop()
        webSocket?.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()
        webSocket = nil
    }

    private func waitForClose() async throws {
        if closeReceived { return }
        try await withCheckedThrowingContinuation { continuation in
            closeContinuation = continuation
            closeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await self?.handleCloseTimeout()
            }
        }
    }

    private func handleCloseTimeout() {
        guard let continuation = closeContinuation else { return }
        closeContinuation = nil
        audio?.stop()
        webSocket?.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()
        webSocket = nil
        continuation.resume(throwing: LiveSessionError.closeTimedOut)
    }

    private func receiveLoop() async {
        guard let webSocket else { return }
        do {
            while !Task.isCancelled {
                let message = try await webSocket.receive()
                let data: Data
                switch message {
                case let .string(text):
                    data = Data(text.utf8)
                case let .data(binary):
                    data = binary
                @unknown default:
                    continue
                }
                try await handle(decoder.decode(ServerEvent.self, from: data))
            }
        } catch is CancellationError {
            return
        } catch {
            let shouldNotify = !closing
            closeTimeoutTask?.cancel()
            audio?.stop()
            webSocket.cancel(with: .goingAway, reason: nil)
            self.webSocket = nil
            receiveTask = nil
            closeContinuation?.resume(throwing: error)
            closeContinuation = nil
            if shouldNotify {
                await onEvent(.error(error.localizedDescription))
            }
        }
    }

    private func handle(_ event: ServerEvent) async throws {
        switch event.type {
        case "session.started":
            started = true
            let audio = AudioPipeline(
                onInputData: { [weak self] data in
                    try await self?.sendAudio(data)
                },
                onInputLevel: onInputLevel,
                onOutputLevel: onOutputLevel
            )
            self.audio = audio
            try audio.start()
            await onEvent(.started)

        case "session.output_audio.delta":
            if let base64 = event.values["delta"]?.stringValue,
               let data = Data(base64Encoded: base64) {
                try audio?.play(data)
            }

        case "session.input_transcript.delta", "session.output_transcript.delta":
            guard let delta = event.values["delta"]?.stringValue else { return }
            let speaker: TranscriptRow.Speaker =
                event.type == "session.input_transcript.delta" ? .user : .assistant
            await onEvent(
                .transcript(
                    speaker: speaker,
                    delta: delta,
                    startMilliseconds: event.values["start_ms"]?.intValue ?? 0,
                    endMilliseconds: event.values["end_ms"]?.intValue ?? 0
                )
            )

        case "session.input_audio.muted":
            audio?.setCaptureMuted(true)
            await onEvent(.muted(true))

        case "session.input_audio.unmuted":
            audio?.setCaptureMuted(false)
            await onEvent(.muted(false))

        case "session.closed":
            audio?.stop()
            closeReceived = true
            closeTimeoutTask?.cancel()
            let duration = extractDuration(from: event.values["usage"])
            await onEvent(.closed(durationSeconds: duration))
            closeContinuation?.resume()
            closeContinuation = nil

        case "error":
            let message =
                event.values["error"]?.objectValue?["message"]?.stringValue
                ?? event.values["message"]?.stringValue
                ?? "The GPT-Live session returned an unknown error."
            throw LiveSessionError.server(message)

        default:
            break
        }
    }

    private func sendAudio(_ data: Data) async throws {
        guard started, !closing else { return }
        try await send(ClientEvent.audio(data))
    }

    private func send(_ event: [String: JSONValue]) async throws {
        guard let webSocket else { throw LiveSessionError.notConnected }
        let data = try encoder.encode(event)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LiveSessionError.invalidEvent
        }
        try await webSocket.send(.string(text))
    }

    private func extractDuration(from value: JSONValue?) -> TimeInterval? {
        guard let usage = value?.objectValue else { return nil }
        for key in ["duration_seconds", "total_seconds", "seconds"] {
            if let duration = usage[key]?.doubleValue {
                return duration
            }
        }
        return nil
    }
}

enum LiveSessionError: LocalizedError {
    case notConnected
    case invalidEvent
    case closeTimedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "The GPT-Live connection is not open."
        case .invalidEvent: "Kai could not encode a GPT-Live event."
        case .closeTimedOut: "The session ended without confirmed final usage."
        case let .server(message): message
        }
    }
}
