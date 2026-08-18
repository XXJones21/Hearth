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

/// Who is home and whether the house is answering -- and the way to change who.
///
/// The status strip was already naming the persona, so switching is the label
/// becoming a menu rather than a new control somewhere else. It is the phone's
/// arrangement in a shorter space: the drawer lists the personas above the
/// destinations with a tick on the live one, and tapping one switches. There is
/// no drawer here, so the name that was already on screen carries the list.
///
/// NOT the same thing as Settings' "Start with", which pins a persona for the
/// NEXT connect and writes `ClientPrefs.startPersona`. This switches the live
/// session and writes nothing.
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

    /// Only a menu when there is something to choose. A disconnected house has
    /// no list, and a house with one persona has no choice -- in both cases the
    /// strip stays a label, because a menu that opens onto one disabled row is
    /// a control that lied about being one.
    private var canSwitch: Bool {
        viewModel.connectionStatus == .connected && viewModel.availablePersonas.count > 1
    }

    var body: some View {
        Group {
            if canSwitch {
                Menu {
                    ForEach(viewModel.availablePersonas, id: \.self) { name in
                        Button {
                            viewModel.switchPersona(name)
                        } label: {
                            // A tick rather than a highlight: the menu is a
                            // list of who is HOME, and one of them is answering.
                            if name == viewModel.selectedPersona {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    strip(showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Persona: \(label). Switch.")
            } else {
                strip(showsChevron: false)
            }
        }
        .glassBackgroundEffect()
    }

    /// The strip itself, identical either way. The chevron is the only thing
    /// that changes, and it changes because the affordance did.
    private func strip(showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 14, weight: .medium))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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
