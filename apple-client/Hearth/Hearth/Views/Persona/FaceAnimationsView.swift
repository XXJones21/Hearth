//
//  FaceAnimationsView.swift
//  Hearth
//
//  The face, off its leash. Every state and every reaction, played on demand.
//
//  The desktop has this as the Personas > Animations panel, and it exists for
//  a reason the phone needs more than the desktop does: a reaction only ever
//  fires when the house happens to say something worth reacting to, so
//  "does the sigh look right" is otherwise a question you answer by asking for
//  jokes until one lands. Here it is a button.
//
//  It plays the live persona's own geometry and palette, not a default, so
//  what shows here is what the stage will show.
//

import SwiftUI
import HearthCore

struct FaceAnimationsView: View {
    let geometry: FaceGeometry
    let palette: PersonaPalette

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state: HearthState = .IDLE
    /// The speech amplitude the face would be getting from the player. Driven
    /// by hand here, because there is no voice in this room.
    @State private var mouth: Double = 0
    @State private var lastCue: String?

    private let states: [(String, HearthState)] = [
        ("Idle", .IDLE), ("Listening", .LISTENING),
        ("Thinking", .THINKING), ("Speaking", .SPEAKING),
    ]

    /// Every reaction the harness can name, in the order the wiki lists them.
    private let reactions: [String] = [
        "laughter", "sigh", "surprise", "question", "confirmation",
        "dissatisfaction", "blink",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PersonaFaceView(
                    geometry: geometry, state: state,
                    palette: palette, reducedMotion: reduceMotion
                )
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .background(HearthPalette.fluff)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))

                group("State", why: "the looping playlist the house puts it in") {
                    HStack(spacing: 8) {
                        ForEach(states, id: \.0) { label, value in
                            chip(label, active: value == state) { state = value }
                        }
                    }
                }

                group("Reactions", why: "what the harness names on a sentence") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 8) {
                        ForEach(reactions, id: \.self) { name in
                            chip(name, active: lastCue == name) { fire(name) }
                        }
                    }
                }

                group("Mouth", why: "what the voice's amplitude does to it") {
                    VStack(alignment: .leading, spacing: 6) {
                        Slider(value: $mouth, in: 0...1)
                            .tint(HearthPalette.fennec)
                            .onChange(of: mouth) { _, level in
                                FaceFeed.shared.speechLevel = level
                            }
                        Text("The stage drives this from the PCM actually playing; here it is your thumb.")
                            .font(.system(size: 12))
                            .foregroundStyle(HearthPalette.fawn)
                    }
                }

                if reduceMotion {
                    Text("Reduce Motion is on: blink, saccades and sway are suppressed, and the beats snap instead of easing. The mouth still follows the slider.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(HearthPalette.fawn)
                }
            }
            .padding(18)
        }
        .background(HearthPalette.cream.ignoresSafeArea())
        .navigationTitle("Animations")
        .navigationBarTitleDisplayMode(.inline)
        // Leaving must not strand the stage wearing whatever was being tested:
        // the mouth would hang open at the slider's last value until the next
        // reply moved it.
        .onDisappear {
            FaceFeed.shared.speechLevel = 0
            FaceFeed.shared.cue = nil
        }
    }

    private func fire(_ name: String) {
        lastCue = name
        FaceFeed.shared.cue = FaceCue(
            name: name, at: Date.timeIntervalSinceReferenceDate * 1000)
    }

    @ViewBuilder
    private func group(
        _ title: String, why: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, why: why)
            content()
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? HearthPalette.cream : HearthPalette.roast)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? HearthPalette.ember : HearthPalette.parchment)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(HearthPalette.linen, lineWidth: active ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Animations panel") {
    NavigationStack {
        FaceAnimationsView(geometry: FaceGeometry(), palette: .fallback)
    }
}
