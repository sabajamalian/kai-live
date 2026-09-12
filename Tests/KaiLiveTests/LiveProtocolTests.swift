import Foundation
import Testing
@testable import KaiLive

struct LiveProtocolTests {
    @Test
    func sessionStartUsesLiveModelAndPCM24k() throws {
        let event = ClientEvent.sessionStart(voice: "meridian", instructions: "Be concise")
        #expect(event["type"] == .string("session.start"))

        let session = event["session"]?.objectValue
        #expect(session?["model"] == .string("gpt-live-1"))
        #expect(session?["store"] == .bool(false))

        let audio = session?["audio"]?.objectValue
        let format = audio?["format"]?.objectValue
        #expect(format?["type"] == .string("audio/pcm"))
        #expect(format?["rate"] == .number(24_000))
    }

    @Test
    func decodesTranscriptEvent() throws {
        let data = Data("""
        {
          "type": "session.input_transcript.delta",
          "delta": "Hello",
          "start_ms": 100,
          "end_ms": 500
        }
        """.utf8)

        let event = try JSONDecoder().decode(ServerEvent.self, from: data)
        #expect(event.type == "session.input_transcript.delta")
        #expect(event.values["delta"]?.stringValue == "Hello")
        #expect(event.values["start_ms"]?.intValue == 100)
    }

    @Test
    func audioEventPreservesBytes() throws {
        let bytes = Data([0, 1, 2, 3])
        let event = ClientEvent.audio(bytes)
        let encoded = event["audio"]?.stringValue
        #expect(Data(base64Encoded: encoded ?? "") == bytes)
    }
}
