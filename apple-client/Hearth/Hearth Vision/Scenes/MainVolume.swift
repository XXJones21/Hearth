//
//  MainVolume.swift
//  Hearth Vision
//
//  The resting state: the persona low in the box, cards stacked beside it, the
//  composer along the bottom and house status along the top.
//
//  A dumb stage, and deliberately. Design section 1's one-scene rule puts the
//  entity world at app level and has each host attach it on appear; this file
//  holds no state worth keeping, because in phase 4 it is dismissed while the
//  immersive house takes the same rig. Everything here is either a placement or
//  a subscription.
//
//  Ported in shape from Valinor's SulivanVolumeView, which was device-validated
//  on this path. What is NOT here yet: the pinch-and-hold that promotes the orb
//  into the room (phase 4 -- the rig carries the flourish already, dormant), the
//  journal shelf (phase 3), and the face (phase 2).
//

import SwiftUI
import RealityKit
import HearthCore
import HearthUI
import HearthSpatial

struct MainVolume: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var rig: PersonaRig
    @ObservedObject private var cardStore: CardStore

    /// Paired AND configured. The app owns this; the volume only renders it.
    let ready: Bool

    init(viewModel: ChatViewModel, rig: PersonaRig, ready: Bool) {
        self.viewModel = viewModel
        self.rig = rig
        self._cardStore = ObservedObject(wrappedValue: viewModel.cardStore)
        self.ready = ready
    }

    var body: some View {
        Group {
            if ready {
                stage
            } else {
                waiting
            }
        }
    }

    // MARK: - The stage

    private var stage: some View {
        RealityView { content, _ in
            // Palm-sized and low in the box. The full transform is set rather
            // than just the position because in phase 4 the rig may be
            // returning from the room, carrying a world transform of its own.
            rig.rootEntity.transform = Transform(
                scale: SIMD3<Float>(repeating: 0.22),
                rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                translation: SIMD3<Float>(0, CardOrbitLayout.orbY, 0)
            )
            content.add(rig.rootEntity)

            rig.configure(for: .volumetric)   // billboard halo; bloom is phase 4
            rig.enableInteraction()
            rig.updateState(PersonaState(viewModel.hearthState))
            rig.setConnected(viewModel.connectionAlive)

            // The tick source. visionOS has no CADisplayLink and the volume has
            // no motion tracker, so the scene's own update event drives the
            // animator. The subscription is stored ON THE RIG because this
            // closure returns immediately and a local would be released with it.
            rig.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                rig.update(deltaTime: event.deltaTime)
                // Cheap: both `apply` calls early-return when nothing changed,
                // which is what lets the rig pick up a persona_config that
                // arrives long after the scene was built.
                rig.apply(viewModel.personaPalette)
                if let geometry = viewModel.personaVisualization.faceGeometry {
                    rig.apply(faceGeometry: geometry)
                }
            }
        } update: { content, attachments in
            layoutAttachments(content: content, attachments: attachments)
        } attachments: {
            ForEach(cardStore.cards) { card in
                Attachment(id: card.id) {
                    DynamicComponent(descriptor: card)
                        .frame(maxWidth: 260)
                        .padding(12)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                cardStore.dismiss(card.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                        }
                        .glassBackgroundEffect()
                }
            }
            // What is being said, right now, above the bead. The one piece of
            // conversation the volume shows: history is the transcript window's
            // job (design section 1), not a mode of the stage.
            Attachment(id: Self.liveTextID) {
                LiveText(viewModel: viewModel)
            }
            // The face, when the compute path could not start.
            //
            // Degraded, never faceless: a device without a usable Metal
            // pipeline, or a build whose metallib did not make it into the
            // bundle, gets the same SwiftUI face the phone draws, billboarded
            // in front of the bead. It is flat and it does not bloom, but it is
            // the SAME director driving it, so it blinks and talks correctly.
            if !rig.hasComputeFace {
                Attachment(id: Self.faceFallbackID) {
                    PersonaFaceView(
                        geometry: viewModel.personaVisualization.faceGeometry ?? FaceGeometry(),
                        state: viewModel.hearthState,
                        palette: viewModel.personaPalette)
                        .frame(width: 220, height: 220)
                }
            }
        }
        // A plain pinch on the bead starts a voice turn. Phase 4 adds the
        // two-second hold on the same target for the immersive switch, which is
        // why this is a gesture on the entity rather than a button anywhere.
        .gesture(
            TapGesture()
                .targetedToEntity(rig.tapTarget)
                .onEnded { _ in
                    guard viewModel.connectionStatus == .connected else { return }
                    viewModel.toggleListening()
                }
        )
        .onChange(of: viewModel.hearthState) { _, state in
            rig.updateState(PersonaState(state))
        }
        .onChange(of: viewModel.connectionAlive) { _, alive in
            rig.setConnected(alive)
        }
        // Two amplitudes, one rig input. The bead does not care which half of
        // the turn it is in -- the level IS the state's, because only one of
        // these is moving at a time.
        .onChange(of: viewModel.ttsAmplitude) { _, level in
            rig.audioLevel = level
        }
        .onChange(of: viewModel.micLevel) { _, level in
            if viewModel.isListening { rig.audioLevel = level }
        }
        .ornament(attachmentAnchor: .scene(.top)) {
            HouseStatusOrnament(viewModel: viewModel)
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            ComposerOrnament(viewModel: viewModel)
        }
    }

    /// Shown while the pairing window has the session. Deliberately quiet: the
    /// person is being asked for something in another window, and a second
    /// surface competing for their attention is noise.
    private var waiting: some View {
        VStack(spacing: 8) {
            Text("Hearth")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text("Waiting to be told where the house is.")
                .font(.system(size: 14))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Painted rather than left as glass, and it resolves to ember on this
        // platform -- see PairingWindow for the trait-query reason and the
        // phase 5 question it raises.
        .background(HearthPalette.cream)
    }

    // MARK: - Placement

    private static let liveTextID = "hearth.live-text"
    private static let faceFallbackID = "hearth.face-fallback"

    /// Parent each attachment to the volume and place it. Cards appearing and
    /// expiring under CardStore's TTL show up here as the attachment set
    /// changing, which is why nothing in this file tracks card lifetimes.
    private func layoutAttachments(content: RealityViewContent, attachments: RealityViewAttachments) {
        let cards = cardStore.cards
        for (index, card) in cards.enumerated() {
            guard let entity = attachments.entity(for: card.id) else { continue }
            if entity.parent == nil { content.add(entity) }
            entity.position = CardOrbitLayout.position(index: index, count: cards.count)
        }

        if let live = attachments.entity(for: Self.liveTextID) {
            if live.parent == nil { content.add(live) }
            live.position = SIMD3<Float>(0, CardOrbitLayout.orbY + 0.2, -0.02)
        }

        // The fallback face rides just in front of the bead, at the bead's own
        // height. Only ever present when the compute path failed.
        if let face = attachments.entity(for: Self.faceFallbackID) {
            if face.parent == nil { content.add(face) }
            face.position = SIMD3<Float>(0, CardOrbitLayout.orbY, 0.06)
        }
    }
}
