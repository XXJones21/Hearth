//
//  ChatMessage.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import Foundation

public enum MessageType {
    case user
    case ai
    case system
}

public struct ChatMessage: Identifiable {
    public let id = UUID()
    public let text: String
    public let type: MessageType
    public let personaName: String?
    public let timestamp: Date
    
    public init(text: String, type: MessageType, personaName: String? = nil) {
        self.text = text
        self.type = type
        self.personaName = personaName
        self.timestamp = Date()
    }
}

