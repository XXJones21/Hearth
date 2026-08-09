//
//  HearthMainView.swift
//  Hearth
//
//  The unified portrait scene. One continuous layout in two states, switched
//  by the Chat log toggle in the house shelf:
//    COLLAPSED (default): the stage owns everything above the composer —
//      persona on top, this turn's card in the middle, the spoken caption
//      below. The conversation IS the orb, its cards and its voice.
//    EXPANDED: the stage takes the upper 45% and yields the rest to the
//      attributed timeline feed.
//  The persona is never covered in either state; the card is bounded to a
//  share of the stage and scrolls inside it.
//

import SwiftUI
import HearthCore

struct HearthMainView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var easel = EaselStore.shared

    /// The transcript is opt-in and remembered. Resting state is the stage
    /// alone — the log is history, and history does not need to be on screen
    /// while Sulivan is talking to you.
    @AppStorage("hearth.transcriptShown") private var transcriptShown = false

    /// The right-hand navigation drawer (HouseShelf).
    @State private var shelfOpen = false
    /// Selene's Library, presented full screen over the stage.
    @State private var showJournal = false
    /// Apps and Extensions, likewise.
    @State private var showApps = false
    /// The persona page, likewise.
    @State private var showPersona = false

    private var isIdle: Bool {
        stageState == .IDLE || stageState == .LOADING
    }

    /// What the persona SHOWS, which is not always what the turn reports.
    ///
    /// A drawing outlives the turn that asked for it: the tool returns
    /// immediately, the turn ends, and the render keeps going on the server
    /// for another half minute. Dropping to idle there reads as "finished",
    /// which is why "I'll let you know when it is done" looked like a broken
    /// promise. While the easel is busy the persona stays in thinking, because
    /// it is.
    ///
    /// Only IDLE is overridden. A real listening or speaking state is the
    /// operator's turn and always wins.
    private var stageState: HearthState {
        if easel.isDrawing && viewModel.hearthState == .IDLE { return .THINKING }
        return viewModel.hearthState
    }

    /// Which card the stage holds. With the transcript open the stage only
    /// spotlights the live turn and then releases — the feed below is holding
    /// it, and two copies of one card on screen is the redundancy we just
    /// removed. Collapsed, the stage is the ONLY surface, so the newest card
    /// stays put after the turn ends rather than vanishing with the voice.
    private var stageCard: UiComponentDescriptor? {
        transcriptShown ? viewModel.stageCard : viewModel.cardStore.cards.last
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // THE STAGE — Sulivan (SwiftUI Canvas) plus this turn's card and
                // karaoke caption. RealityKit is reserved for the visionOS
                // immersive window and glb personas (Selene); see
                // PersonaCanvasView for the rationale.
                //
                // With the transcript collapsed the stage takes the whole screen
                // above the composer: the conversation IS the orb, its cards and
                // its voice. Expanded, it yields the lower 55% to the log.
                let stageHeight = transcriptShown ? geo.size.height * 0.45 : geo.size.height
                personaStage(height: stageHeight)
                    .frame(maxHeight: stageHeight)
                    .background(
                        LinearGradient(
                            colors: [HearthPalette.fluff, HearthPalette.glowtint],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.hearthState == .IDLE && viewModel.connectionStatus == .connected {
                            viewModel.toggleListening()
                        }
                    }

                if transcriptShown {
                    TimelineFeed(viewModel: viewModel)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HouseStatusBar(viewModel: viewModel)
                BottomInputBar(viewModel: viewModel)
            }
            .animation(.spring(duration: 0.35), value: transcriptShown)
        }
        .background(HearthPalette.cream.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.spring(duration: 0.3)) { shelfOpen = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HearthPalette.fawn)
                    .padding(12)
            }
            .accessibilityLabel("Menu")
            .opacity(shelfOpen ? 0 : 1)
        }
        .overlay {
            if shelfOpen {
                HearthPalette.roast.opacity(0.34)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) { shelfOpen = false }
                    }
            }
        }
        .overlay(alignment: .trailing) {
            if shelfOpen {
                HouseShelf(
                    viewModel: viewModel,
                    transcriptShown: $transcriptShown,
                    isOpen: $shelfOpen,
                    onOpenJournal: { showJournal = true },
                    onOpenApps: { showApps = true },
                    onOpenPersona: { showPersona = true }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .fullScreenCover(isPresented: $viewModel.showSettings) {
            HearthSettingsView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showJournal) {
            JournalView()
        }
        .fullScreenCover(isPresented: $showApps) {
            AppsView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showPersona) {
            PersonaView(viewModel: viewModel)
        }
    }

    // MARK: - The stage (orb over this turn's card + caption)

    /// Stacked, not overlaid: the orb keeps the slack above while the card and
    /// caption take exactly the height they need at the bottom. Overlaying them
    /// let a tall card — the one that forced this, a dashboard, ran about 550pt
    /// — bury the persona entirely. The card scrolls inside a share of the
    /// stage rather than pushing the orb off the top.
    private func personaStage(height: CGFloat) -> some View {
        let card = stageCard
        // The card gets a bounded share and scrolls inside it. It must never
        // take so much that the persona is squeezed out — the visualization is
        // the point of the stage and stays visible at all times.
        let cardCeiling = height * (transcriptShown ? 0.34 : 0.46)
        return VStack(spacing: 12) {
            // Persona on top, always. It keeps whatever slack is left over.
            ZStack {
                // The renderer is chosen by the persona's own config, never by
                // name: `sphere_particle` keeps the 2D canvas, `glb_animated`
                // mounts RealityKit. A glb persona whose USDZ clips have not
                // reached the server yet falls back to its orb rather than
                // showing an empty volume, so Sage arrives with no code change.
                if viewModel.personaVisualization.canRenderModel {
                    PersonaModelView(
                        visualization: viewModel.personaVisualization,
                        state: stageState
                    )
                } else {
                    PersonaCanvasView(
                        state: stageState,
                        pulse: Double(viewModel.ttsAmplitude),
                        palette: viewModel.personaPalette
                    )
                }
                // The clock crowns an EMPTY stage; once a card is resting on it
                // the clock would just be chrome stacked on content.
                if isIdle && card == nil {
                    IdleClockOverlay()
                        .transition(.opacity)
                }
            }
            .frame(minHeight: height * 0.22, maxHeight: .infinity)

            // Card in the middle.
            if let card {
                ScrollView {
                    DynamicComponent(descriptor: card)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: 460, maxHeight: cardCeiling)
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Caption below the card.
            if !viewModel.spokenSentence.isEmpty {
                spokenSentenceBand(ceiling: height * (transcriptShown ? 0.30 : 0.36))
            }
        }
        .padding(.bottom, 16)
        .animation(.easeInOut(duration: 0.45), value: isIdle)
        .animation(.easeInOut(duration: 0.28), value: card?.id)
    }

    /// One growing bubble holding the reply so far — the shape the visionOS
    /// transcript card uses, so the two clients read alike. Sentences are
    /// appended as they are HEARD (see ChatViewModel.spokenSentence), so it
    /// fills at the pace of the voice. Bounded and scrolled to the tail: it is
    /// still a caption sharing the stage with the persona, not a transcript.
    private func spokenSentenceBand(ceiling: CGFloat) -> some View {
        // The bubble must HUG its text, so every modifier here has to stay
        // vertically inflexible. `.frame(maxHeight:)` is what broke this
        // before: a max-height frame is flexible, so the VStack handed it a
        // share of the leftover stage and it opened at full ceiling height
        // with the text stranded in empty space. Instead the text hugs
        // (fixedSize) and growth is bounded by a line limit derived from the
        // ceiling, keeping the tail visible once it fills up.
        captionText
            .lineLimit(Self.captionLines(ceiling: ceiling))
            .truncationMode(.head)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520)
            .animation(.easeOut(duration: 0.2), value: viewModel.spokenSentence)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(HearthPalette.glowtint, in: bandShape)
            .overlay(bandShape.stroke(HearthPalette.bubbleLine, lineWidth: 1))
            .hearthSoftShadow()
            .padding(.horizontal, 16)
    }

    /// How many lines fit in the caption's share of the stage, at ~19pt a line.
    private static func captionLines(ceiling: CGFloat) -> Int {
        max(2, min(12, Int(ceiling / 19)))
    }

    private var captionText: some View {
        Text(viewModel.spokenSentence)
            .font(.callout.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(HearthPalette.roast)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }


    private var bandShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }
}

// MARK: - Idle clock (crowns the persona)

private struct IdleClockOverlay: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(HearthPalette.fawn)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HearthPalette.roast)
            .padding(.top, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
