//
//  Ornaments.swift
//  Hearth Vision
//
//  The volume's two edges: house status along the top, the composer along the
//  bottom.
//
//  Ornaments rather than content, because both are ABOUT the volume rather than
//  in it. Design section 1 asks for exactly this split, and the platform agrees:
//  an ornament rides outside the bounded box, so neither of these steals depth
//  from the stage or occludes the bead.
//
//  Vision-native rather than shared, and that is a considered call. The phone's
//  HouseStatusBar and BottomInputBar are shaped for a 390pt column with a
//  keyboard sliding under them; an ornament is a short horizontal strip with no
//  keyboard of its own. Sharing them would mean parameterising both for a
//  layout neither was written for. They stay in the iOS target until something
//  actually wants them twice.
//

import SwiftUI
import HearthCore
import HearthUI

// MARK: - Status

/// Who is home and whether the house is answering.
struct HouseStatusOrnament: View {
    @ObservedObject var viewModel: ChatViewModel

    private var dotColor: Color {
        switch viewModel.connectionStatus {
        case .connected:    return HearthPalette.sage
        case .connecting:   return HearthPalette.honey
        case .disconnected: return HearthPalette.clay
        }
    }

    private var label: String {
        switch viewModel.connectionStatus {
        case .connected:    return viewModel.currentPersonaName
        case .connecting:   return "Reaching for the house..."
        case .disconnected: return "The house is not answering"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassBackgroundEffect()
        // The dot is decoration; the label already says it. Merging them stops
        // VoiceOver reading a colour swatch as a separate element.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Composer

/// Type, or hold the mic. The bead itself is the third way in -- a pinch on it
/// starts a turn -- so this is for the times speaking aloud is the wrong move.
struct ComposerOrnament: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    /// A turn needs a live socket and nothing already in flight. The controls
    /// dim rather than failing on tap, which is the phone's rule too.
    private var canAct: Bool {
        viewModel.connectionStatus == .connected && !viewModel.isWaitingForResponse
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("Say something to the house", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .frame(width: 320)
                .focused($focused)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canAct)

            Divider().frame(height: 22)

            Button {
                viewModel.toggleListening()
            } label: {
                Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                    .font(.title2)
                    .foregroundStyle(viewModel.isListening ? HearthPalette.ember : .primary)
            }
            .buttonStyle(.plain)
            .disabled(!canAct && !viewModel.isListening)
            .accessibilityLabel(viewModel.isListening ? "Stop listening" : "Start listening")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
        .opacity(canAct || viewModel.isListening ? 1 : 0.5)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canAct else { return }
        viewModel.sendMessage(text)
        draft = ""
    }
}
