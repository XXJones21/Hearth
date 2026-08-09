//
//  HearthState.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import Foundation

public enum HearthState {
    case LOADING    // Server connection in progress
    case IDLE       // Default state, waiting for user to start
    case LISTENING  // Streaming audio, waiting for speech
    case THINKING   // Server processing (transcription received)
    case SPEAKING   // TTS audio playing
}

