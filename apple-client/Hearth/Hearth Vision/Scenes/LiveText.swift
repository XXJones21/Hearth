//
//  LiveText.swift
//  Hearth Vision
//
//  What is being said, right now, on a glass card above the bead: your words
//  while listening, a hint while thinking, the house's words while speaking.
//  Faded out when idle, because a card that always says something is a card
//  nobody reads.
//
//  This is the volume's ONLY conversation surface, and that is design section
//  1's line: history is a thing in the room -- the transcript window -- not a
//  mode of the stage. The phone conflates the two because a phone has one
//  screen; the headset does not have to.
//
//  Ported from Valinor's LiveTranscriptCardView. It reads published state and
//  owns none, so it needs no lifecycle of its own.
//

import SwiftUI
import HearthCore

struct LiveText: View {
    @ObservedObject var viewModel: ChatViewModel

    private var isActive: Bool {
        switch viewModel.hearthState {
        case .LISTENING, .THINKING, .SPEAKING: return true
        case .LOADING, .IDLE: return false
        }
    }

    private var speaker: String {
        viewModel.hearthState == .LISTENING ? "You" : viewModel.currentPersonaName
    }

    /// Each state has a real source and a placeholder for the gap before the
    /// first token arrives. The placeholder is never blank: a card that appears
    /// empty reads as broken rather than as waiting.
    private var text: String {
        switch viewModel.hearthState {
        case .LISTENING:
            return viewModel.liveTranscription.isEmpty ? "Listening..." : viewModel.liveTranscription
        case .THINKING:
            return viewModel.thinkingText.isEmpty ? "Thinking..." : viewModel.thinkingText
        case .SPEAKING:
            return viewModel.liveTranscript.isEmpty ? "Speaking..." : viewModel.liveTranscript
        case .LOADING, .IDLE:
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(speaker.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            // Compact by default, growing with the response as it accumulates.
            Text(text)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 360, alignment: .leading)
        // Glass here, not the brand surface. A card floating over passthrough
        // is the platform's idiom and the one place the ember question does not
        // arise -- system materials resolve themselves.
        .glassBackgroundEffect()
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: text)
    }
}
