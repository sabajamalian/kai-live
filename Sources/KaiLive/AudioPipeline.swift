@preconcurrency import AVFoundation
import Foundation

final class AudioPipeline: @unchecked Sendable {
    typealias InputHandler = @Sendable (Data) async throws -> Void
    typealias LevelHandler = @MainActor @Sendable (Float) -> Void

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let inputHandler: InputHandler
    private let onInputLevel: LevelHandler
    private let onOutputLevel: LevelHandler
    private let processingQueue = DispatchQueue(label: "KaiLive.AudioProcessing")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!
    private var captureMuted = false
    private var converter: AVAudioConverter?
    private let inputStream: AsyncStream<Data>
    private let inputContinuation: AsyncStream<Data>.Continuation
    private var inputTask: Task<Void, Never>?

    init(
        onInputData: @escaping InputHandler,
        onInputLevel: @escaping LevelHandler,
        onOutputLevel: @escaping LevelHandler
    ) {
        let stream = AsyncStream<Data>.makeStream()
        inputStream = stream.stream
        inputContinuation = stream.continuation
        inputHandler = onInputData
        self.onInputLevel = onInputLevel
        self.onOutputLevel = onOutputLevel
    }

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: targetFormat)

        input.installTap(onBus: 0, bufferSize: 2_400, format: inputFormat) { [weak self] buffer, _ in
            self?.processInput(buffer)
        }

        try engine.start()
        player.play()
        inputTask = Task { [inputStream, inputHandler] in
            for await data in inputStream {
                do {
                    try await inputHandler(data)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        converter = nil
        inputContinuation.finish()
        inputTask?.cancel()
        inputTask = nil
        Task { @MainActor in
            onInputLevel(0)
            onOutputLevel(0)
        }
    }

    func setCaptureMuted(_ muted: Bool) {
        processingQueue.async { [weak self] in
            self?.captureMuted = muted
        }
    }

    func play(_ data: Data) throws {
        guard data.count.isMultiple(of: 2) else {
            throw AudioPipelineError.incompleteSample
        }
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            throw AudioPipelineError.bufferCreationFailed
        }
        buffer.frameLength = frameCount
        data.copyBytes(to: buffer.mutableAudioBufferList.pointee.mBuffers.mData!.assumingMemoryBound(to: UInt8.self), count: data.count)

        let level = Self.level(of: data)
        Task { @MainActor in onOutputLevel(level) }
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in self?.onOutputLevel(0) }
        }
    }

    private func processInput(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.copy(buffer) else { return }
        processingQueue.async { [weak self, copy] in
            guard let self, !captureMuted, let converter else { return }

            let ratio = targetFormat.sampleRate / copy.format.sampleRate
            let capacity = AVAudioFrameCount(Double(copy.frameLength) * ratio) + 1
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                return
            }

            var conversionError: NSError?
            let source = InputBufferSource(buffer: copy)
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                source.next(inputStatus)
            }

            guard status != .error, conversionError == nil, output.frameLength > 0,
                  let dataPointer = output.audioBufferList.pointee.mBuffers.mData else {
                return
            }

            let byteCount = Int(output.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: dataPointer, count: byteCount)
            let level = Self.level(of: data)
            Task { @MainActor in self.onInputLevel(level) }
            self.inputContinuation.yield(data)
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameLength
        ) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<min(source.count, destination.count) {
            guard let sourceData = source[index].mData, let destinationData = destination[index].mData else {
                continue
            }
            memcpy(destinationData, sourceData, Int(source[index].mDataByteSize))
            destination[index].mDataByteSize = source[index].mDataByteSize
        }
        return copy
    }

    static func level(of data: Data) -> Float {
        guard data.count >= 2 else { return 0 }
        return data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            let sum = samples.reduce(0.0) { partial, sample in
                let normalized = Double(sample) / Double(Int16.max)
                return partial + normalized * normalized
            }
            return Float(min(1, sqrt(sum / Double(samples.count)) * 4))
        }
    }
}

private final class InputBufferSource: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if supplied {
            status.pointee = .noDataNow
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
    }
}

enum AudioPipelineError: LocalizedError {
    case incompleteSample
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .incompleteSample: "Received an incomplete PCM audio sample."
        case .bufferCreationFailed: "Could not allocate an audio playback buffer."
        }
    }
}
