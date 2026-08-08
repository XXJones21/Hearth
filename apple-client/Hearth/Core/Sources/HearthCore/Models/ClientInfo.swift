//
//  ClientInfo.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import Foundation

struct ClientInfo: Codable {
    let action: String
    let platform: String
    let capabilities: Capabilities
    let audioFormat: AudioFormat
    let deviceContext: DeviceContext?

    enum CodingKeys: String, CodingKey {
        case action
        case platform
        case capabilities
        case audioFormat = "audio_format"
        case deviceContext = "device_context"
    }

    struct Capabilities: Codable {
        let audio: Bool
        let spatial: Bool
        let voiceInput: Bool
        let textInput: Bool
        let vision: Bool
        let stt: String?
        let sttEngine: String?
        let uiRender: Bool

        enum CodingKeys: String, CodingKey {
            case audio
            case spatial
            case voiceInput = "voice_input"
            case textInput = "text_input"
            case vision
            case stt
            case sttEngine = "stt_engine"
            case uiRender = "ui_render"
        }
    }

    struct AudioFormat: Codable {
        let sampleRate: Int?
        let bitDepth: Int?
        let channels: Int?

        enum CodingKeys: String, CodingKey {
            case sampleRate = "sample_rate"
            case bitDepth = "bit_depth"
            case channels
        }
    }

    // Device context for the Valar gateway (timezone-aware tools: weather,
    // timers, briefs). Mirrors the Echo client's handshake shape; location
    // is omitted for now (a phone has no fixed home location).
    struct DeviceContext: Codable {
        let timezone: String
        let locale: String
        let units: String

        static func current() -> DeviceContext {
            return DeviceContext(
                timezone: TimeZone.current.identifier,
                locale: Locale.current.identifier(.bcp47),
                units: Locale.current.measurementSystem == .us ? "imperial" : "metric"
            )
        }
    }

    static func iosTextOnly() -> ClientInfo {
        return ClientInfo(
            action: "client_info",
            platform: "ios",
            capabilities: Capabilities(
                audio: false,
                spatial: false,
                voiceInput: false,
                textInput: true,
                vision: false,
                stt: nil,
                sttEngine: nil,
                uiRender: false
            ),
            audioFormat: AudioFormat(sampleRate: nil, bitDepth: nil, channels: nil),
            deviceContext: DeviceContext.current()
        )
    }

    static func iosAudioEnabled() -> ClientInfo {
        return ClientInfo(
            action: "client_info",
            platform: "ios",
            capabilities: Capabilities(
                audio: true,
                spatial: false,
                voiceInput: true,
                textInput: true,
                vision: true,
                stt: "local",
                sttEngine: "apple_speech",
                uiRender: true
            ),
            audioFormat: AudioFormat(
                sampleRate: nil,
                bitDepth: nil,
                channels: nil
            ),
            deviceContext: DeviceContext.current()
        )
    }
}

struct ClientInfoAck: Codable {
    let action: String
    let status: String
    let serverCapabilities: ServerCapabilities
    
    enum CodingKeys: String, CodingKey {
        case action
        case status
        case serverCapabilities = "server_capabilities"
    }
    
    struct ServerCapabilities: Codable {
        let audioGeneration: Bool
        let voiceCloning: Bool
        let spatialSupport: Bool
        
        enum CodingKeys: String, CodingKey {
            case audioGeneration = "audio_generation"
            case voiceCloning = "voice_cloning"
            case spatialSupport = "spatial_support"
        }
    }
}

