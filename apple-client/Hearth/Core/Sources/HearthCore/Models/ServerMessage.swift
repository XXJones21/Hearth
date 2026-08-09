//
//  ServerMessage.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import Foundation

struct ServerMessage: Codable {
    let action: String
    
    // AI Response fields
    let text: String?
    let personaName: String?
    let hasAudio: Bool?
    let intent: String?
    let modelUsed: String?
    let confidence: Double?
    let hadThinkingMessage: Bool?
    let sessionId: String?
    let timestamp: String?
    
    // Fast Response fields (HRM evaluation)
    let qualityScore: Double?
    let escalationTriggered: Bool?
    
    // Partial transcription fields
    let isFinal: Bool?
    
    // Error fields
    let message: String?

    // Pong fields
    let status: String?
    let serverIp: String?
    let stats: [String: AnyCodable]?

    // state_update fields (server-announced state machine, Valar Phase B)
    let state: String?
    let stage: String?

    // session_ended fields (server idle watchdog)
    let reason: String?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case action
        case text
        case personaName = "persona_name"
        case hasAudio = "has_audio"
        case intent
        case modelUsed = "model_used"
        case confidence
        case hadThinkingMessage = "had_thinking_message"
        case sessionId = "session_id"
        case timestamp
        case qualityScore = "quality_score"
        case escalationTriggered = "escalation_triggered"
        case isFinal = "is_final"
        case message
        case status
        case serverIp = "server_ip"
        case stats
        case state
        case stage
        case reason
        case summary
    }
}

// Helper for decoding Any type in stats
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}

struct PongResponse: Codable {
    let action: String
    let status: String
    let serverIp: String?
    let stats: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case action
        case status
        case serverIp = "server_ip"
        case stats
    }
}

struct WavFileInfo: Codable {
    let action: String
    let filename: String?
    let sampleRate: Int?
    let duration: Double?
    let wavChunks: Int?  // Number of chunks if audio is chunked (iOS)
    let wavSize: Int?  // Total size of WAV file
    
    enum CodingKeys: String, CodingKey {
        case action
        case filename
        case sampleRate = "sample_rate"
        case duration
        case wavChunks = "wav_chunks"
        case wavSize = "wav_size"
    }
}
