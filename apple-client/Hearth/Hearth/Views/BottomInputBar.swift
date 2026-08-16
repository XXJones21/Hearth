//
//  BottomInputBar.swift
//  Hearth
//
//  Voice-first bottom control (Echo parity). A single state-reactive
//  "tap to talk" button drives the built-in speech recognition
//  (viewModel.toggleListening). A keyboard affordance reveals a text field on
//  demand for typing, so the resting state is one button — not a split
//  mic + input box. The mic/STT and send flows live in ChatViewModel.
//

import SwiftUI
import HearthCore

struct BottomInputBar: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var typing = false
    @State private var inputText = ""
    @State private var pulse = false
    @FocusState private var isInputFocused: Bool

    private let primary = HearthPalette.fennec

    var body: some View {
        VStack(spacing: 12) {
            if !viewModel.liveTranscription.isEmpty {
                liveTranscriptionOverlay
            }

            if typing {
                inputRow
            } else {
                talkRow
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .background(
            HearthPalette.fluff
                .overlay(alignment: .top) { HearthPalette.linen.frame(height: 1) }
        )
        .animation(.spring(duration: 0.25), value: typing)
    }

    // MARK: - Talk button (resting state)

    private var talkRow: some View {
        ZStack {
            Button(action: { viewModel.toggleListening() }) {
                HStack(spacing: 10) {
                    Image(systemName: talkIcon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(talkLabel)
                        .font(.headline)
                }
                .foregroundStyle(HearthPalette.roast)
                .frame(maxWidth: 240)
                .padding(.vertical, 16)
                .background(
                    // While listening the glow rides the actual microphone
                    // (viewModel.micLevel), so a muted mic and a dead route
                    // LOOK different from a working one -- the fixed timer
                    // pulse looked identical either way.
                    Capsule().fill(talkColor)
                        .shadow(color: talkColor.opacity(0.5),
                                radius: pulse ? 10 + CGFloat(viewModel.micLevel) * 14 : 8,
                                y: 4)
                )
                .scaleEffect(pulse ? 1.02 + CGFloat(viewModel.micLevel) * 0.05 : 1.0)
                .animation(.easeOut(duration: 0.12), value: viewModel.micLevel)
            }
            .disabled(!talkEnabled)
            .accessibilityLabel(talkLabel)
            .onChange(of: viewModel.hearthState) { _, newState in
                let listening = (newState == .LISTENING)
                withAnimation(listening
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .default) {
                    pulse = listening
                }
            }

            // Keyboard affordance (trailing) — switch to typing. It is the only
            // thing flanking the talk button: the whole app is three buttons,
            // and everything else lives in the house shelf.
            HStack {
                Spacer()
                Button {
                    typing = true
                    isInputFocused = true
                    // The face watches where the words come from. `typing`, not
                    // focus: a dismissed keyboard drops focus while the
                    // composer is still up and still where someone is looking.
                    FaceFeed.shared.composerUp = true
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(HearthPalette.fawn)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Type a message")
            }
        }
    }

    private var talkLabel: String {
        switch viewModel.hearthState {
        // The label is the contract: once there are words, a tap SENDS them
        // (a pause sends on its own). The discard is the stage tap.
        case .LISTENING:
            return viewModel.liveTranscription.isEmpty ? "Listening…" : "Tap to send"
        case .THINKING:  return "Thinking…"
        case .SPEAKING:  return "Tap to interrupt"
        default:         return "Tap to talk"
        }
    }

    private var talkIcon: String {
        switch viewModel.hearthState {
        case .LISTENING: return "waveform"
        case .THINKING:  return "ellipsis"
        case .SPEAKING:  return "speaker.wave.2.fill"
        default:         return "mic.fill"
        }
    }

    private var talkColor: Color {
        switch viewModel.hearthState {
        case .LISTENING: return HearthPalette.honey    // warm "live" cue
        case .SPEAKING:  return HearthPalette.ember
        default:         return primary                // fennec
        }
    }

    private var talkEnabled: Bool {
        // SPEAKING included: the mic mid-reply is barge-in -- toggleListening
        // cuts the voice and opens a listening turn. Only THINKING stays
        // dead, because there is nothing to interrupt yet.
        viewModel.connectionStatus == .connected &&
        viewModel.hearthState != .THINKING &&
        viewModel.hearthState != .LOADING
    }

    // MARK: - Typing (on demand)

    private var inputRow: some View {
        HStack(spacing: 10) {
            Button {
                typing = false
                isInputFocused = false
                FaceFeed.shared.composerUp = false
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(HearthPalette.fawn)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Back to voice")

            TextField("Message…", text: $inputText)
                // Where the words are being typed, published for the face to
                // look at. The field itself, not the whole bar: the face
                // should watch the text, not the send button.
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { FaceFeed.shared.composerFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in
                                FaceFeed.shared.composerFrame = frame
                            }
                            .onDisappear { FaceFeed.shared.composerFrame = nil }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(HearthPalette.parchment)
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(HearthPalette.linen, lineWidth: 1)
                )
                .foregroundStyle(HearthPalette.roast)
                .tint(HearthPalette.fennec)
                .focused($isInputFocused)
                .disabled(viewModel.connectionStatus != .connected || viewModel.isWaitingForResponse)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? HearthPalette.roast : HearthPalette.fawn.opacity(0.5))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        viewModel.connectionStatus == .connected &&
        !viewModel.isWaitingForResponse
    }

    private func sendMessage() {
        guard canSend else { return }
        let text = inputText
        inputText = ""
        viewModel.sendMessage(text)
    }

    // MARK: - Live transcription

    private var liveTranscriptionOverlay: some View {
        VStack(spacing: 4) {
            Text(viewModel.liveTranscription)
                .font(.subheadline)
                .foregroundStyle(HearthPalette.roast)
            // The silence auto-submit was invisible, so people were
            // surprise-sent mid-sentence. Naming the mechanic is the
            // lightweight honest version of a countdown.
            Text("sends when you pause, or tap the button")
                .font(.system(size: 10.5))
                .foregroundStyle(HearthPalette.fawn)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(HearthPalette.glowtint)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.2), value: viewModel.liveTranscription)
    }
}
