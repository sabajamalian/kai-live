import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { value } else { nil }
    }

    var intValue: Int? {
        if case let .number(value) = self { Int(value) } else { nil }
    }

    var doubleValue: Double? {
        if case let .number(value) = self { value } else { nil }
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { value } else { nil }
    }
}

struct ServerEvent: Decodable, Sendable {
    let type: String
    let values: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: JSONValue] = [:]
        for key in container.allKeys {
            values[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        type = values["type"]?.stringValue ?? ""
        self.values = values
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
    }
}

enum ClientEvent {
    static func sessionStart(voice: String, instructions: String) -> [String: JSONValue] {
        [
            "type": .string("session.start"),
            "event_id": .string(UUID().uuidString),
            "session": .object([
                "model": .string("gpt-live-1"),
                "instructions": .string(instructions),
                "store": .bool(false),
                "audio": .object([
                    "format": .object([
                        "type": .string("audio/pcm"),
                        "rate": .number(24_000)
                    ]),
                    "output": .object([
                        "voice": .string(voice)
                    ])
                ]),
                "delegation": .object([
                    "type": .string("client")
                ])
            ])
        ]
    }

    static func audio(_ data: Data) -> [String: JSONValue] {
        [
            "type": .string("session.input_audio.append"),
            "audio": .string(data.base64EncodedString())
        ]
    }

    static func mute(_ muted: Bool, eventID: String) -> [String: JSONValue] {
        [
            "type": .string(muted ? "session.input_audio.mute" : "session.input_audio.unmute"),
            "event_id": .string(eventID)
        ]
    }

    static func close() -> [String: JSONValue] {
        [
            "type": .string("session.close"),
            "event_id": .string(UUID().uuidString)
        ]
    }
}
