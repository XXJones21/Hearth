//
//  ChatMessage.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import Foundation

/// String-backed and Codable so transcripts survive a relaunch
/// (TranscriptStore). The raw values are the wire-ish vocabulary desktop
/// already persists; an unknown value in an old file decodes as nil and the
/// row is dropped rather than sinking the whole transcript.
public enum MessageType: String, Codable {
    case user
    case ai
    case system
}

public struct ChatMessage: Identifiable, Codable {
    public let id: UUID
    public let text: String
    public let type: MessageType
    public let personaName: String?
    public let timestamp: Date

    public init(text: String, type: MessageType, personaName: String? = nil) {
        self.id = UUID()
        self.text = text
        self.type = type
        self.personaName = personaName
        self.timestamp = Date()
    }
}
