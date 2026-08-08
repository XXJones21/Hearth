//
//  ChatMessage.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import Foundation

enum MessageType {
    case user
    case ai
    case system
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let type: MessageType
    let personaName: String?
    let timestamp: Date
    
    init(text: String, type: MessageType, personaName: String? = nil) {
        self.text = text
        self.type = type
        self.personaName = personaName
        self.timestamp = Date()
    }
}

