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
//  into the room (phase 4 -- the rig carries the flourish already, dormant).
//
//  The journals are NOT here. Books loose in the volume floated with nothing to
//  stand on and cluttered a stage meant to hold a persona; they live in the
//  centre slot now, as ENTITIES on shelves you scroll. See
//  JournalLibraryEntity for why they are not a window of their own.
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

    /// The open destination, or nil for the plain stage.
    ///
    /// Opening one slides the orb to the left of the box and puts the view in
    /// the middle: the desktop's three-slot frame, which a volume is the one
    /// Apple surface with room for.
    @State private var surface: HouseSurface?

    /// The library, built once and held. Shelves of spine-out books that live
    /// in this volume's centre slot -- see JournalLibraryEntity for why they are
    /// not a window of their own.
    @State private var libraryEntity = JournalLibraryEntity()
    @StateObject private var library = JournalLibrary()

    /// The journal being read, or nil for the shelves.
    @State private var reading: JournalBook?

    /// Scroll state for the shelves. `hasScrolled` is the whole arbitration
    /// between the two pinches: a drag that travelled was a scroll, and the tap
    /// ending it opens nothing.
    @State private var scrollAtGestureStart: Float = 0
    @State private var hasScrolled = false

    /// The rooms the library laid out, mirrored so the attachment builder can
    /// see them. The entity owns the truth; this is the redraw trigger.
    @State private var libraryRooms: [JournalLibraryEntity.Room] = []

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

            // Where the orb lives, and the three places a behaviour can send
            // it. Registered by the host because only the host knows where it
            // put things -- the director resolves names, it does not survey the
            // scene. Design section 4's targets "are entities, and the entities
            // are simply closer" in the volume: these are that, at desk scale.
            rig.homePosition = SIMD3<Float>(0, CardOrbitLayout.orbY, 0)
            // Toward the library. There is no shelf ENTITY in the stage any
            // more -- the books live in the Journal panel, where they can be
            // scrolled -- so this names where that panel opens. The orb flying
            // toward the library it is about to open is the point; whether the
            // books are already on screen is not.
            rig.behavior.setTarget("shelf",
                at: SIMD3<Float>(0.16, CardOrbitLayout.orbY + 0.05, 0.02))
            // Out over the cards, where work is visible.
            rig.behavior.setTarget("workspace",
                at: SIMD3<Float>(CardOrbitLayout.leftX * 0.55, CardOrbitLayout.orbY + 0.05, 0.02))
            // Up and back a little: the spatial version of looking away to
            // think, which is what the face's thinking beats already do.
            rig.behavior.setTarget("recall",
                at: SIMD3<Float>(-0.05, CardOrbitLayout.orbY + 0.11, -0.05))


            // The centre slot's 3D half. Hidden until the Journal button asks
            // for it; the orb slides left to make room.
            libraryEntity.root.position = SIMD3<Float>(0.10, 0.06, 0.02)
            libraryEntity.root.isEnabled = false
            content.add(libraryEntity.root)

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
            // An opened journal. JournalBookView, the phone's own reading
            // view, unchanged -- the library is new; what is written in a
            // journal is not.
            if let reading {
                Attachment(id: Self.readerID) {
                    VStack(spacing: 0) {
                        HStack {
                            Button {
                                self.reading = nil
                            } label: {
                                Label("Shelves", systemImage: "chevron.left")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .tint(HearthPalette.ember)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(HearthPalette.parchment)

                        JournalBookView(book: reading)
                    }
                    .frame(width: 420, height: 560)
                    .background(HearthPalette.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            // The room labels, floating over the shelves they name. Parented
            // to the SCROLLER, so a caption travels with its books rather than
            // sitting still while they move past underneath it.
            ForEach(libraryRooms) { room in
                Attachment(id: room.id) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(room.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HearthPalette.roast)
                        Text(room.caption)
                            .font(.system(size: 9.5))
                            .italic()
                            .foregroundStyle(HearthPalette.fawn)
                    }
                }
            }
            Attachment(id: Self.mastheadID) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Journal")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(HearthPalette.roast)
                    Text("kept by Selene")
                        .font(.system(size: 10))
                        .italic()
                        .foregroundStyle(HearthPalette.fawn)
                }
            }
            // The centre slot, for the four FLAT destinations. Journal is not
            // one: its centre slot is the library's entities, and a panel
            // behind them was a plane standing in front of the shelves.
            if let surface, surface != .journal {
                Attachment(id: Self.surfaceID) {
                    HouseSurfacePanel(viewModel: viewModel, surface: surface) {
                        self.surface = nil
                    }
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
            VStack(spacing: 8) {
                ComposerOrnament(viewModel: viewModel)
                HouseShelfOrnament(active: $surface)
            }
        }
        // The slide. `homePosition` is what the behaviour director returns to,
        // so moving it moves the orb's whole notion of where it lives -- a
        // performance mid-flight lands in the new place rather than snapping
        // back to the old one afterwards.
        // Design section 5's second open path: consulting a journal opens the
        // library. WHICH journal is the library's own business -- it watches the
        // same reply this does, so nothing has to be threaded between two
        // sibling scenes to say one string.
        .onChange(of: viewModel.liveTranscript) { _, text in
            guard rig.behavior.isPerforming, !text.isEmpty else { return }
            let title = Self.firstQuotedTitle(in: text)
            guard !title.isEmpty, let found = libraryEntity.book(matchingTitle: title) else { return }
            surface = .journal
            reading = found
        }
        .task { await library.load() }
        .onChange(of: library.allBooks.map(\.id)) { _, _ in rebuildLibrary() }
        .onChange(of: viewModel.personaPalette) { _, _ in rebuildLibrary() }
        // Drag to scroll the shelves. Clamped by the library itself, because
        // there is no scroll bar in a volume to show you where you went.
        .gesture(
            DragGesture()
                .targetedToEntity(libraryEntity.root)
                .onChanged { value in
                    if abs(value.translation.height) > 6 { hasScrolled = true }
                    libraryEntity.scroll = scrollAtGestureStart
                        + Float(value.translation.height) * -0.0009
                }
                .onEnded { _ in scrollAtGestureStart = libraryEntity.scroll }
        )
        // Pinch a spine to read it. Same pinch as the scroll, told apart by
        // whether it moved -- which is what a ScrollView would have arbitrated
        // for free and what a RealityView has to do for itself.
        .gesture(
            SpatialTapGesture()
                .targetedToEntity(libraryEntity.root)
                .onEnded { value in
                    defer { hasScrolled = false }
                    guard !hasScrolled else { return }
                    reading = libraryEntity.book(for: value.entity)
                }
        )
        .onChange(of: surface) { _, open in
            // Journal fills the centre slot with ENTITIES rather than a panel:
            // its books are three-dimensional and an attachment is a SwiftUI
            // view rendered onto a plane. The orb slides for it like any other
            // destination, because it is one.
            libraryEntity.root.isEnabled = (open == .journal)
            if open != .journal { reading = nil }
            withAnimation(.easeInOut(duration: 0.35)) {
                rig.homePosition = SIMD3<Float>(
                    open == nil ? 0 : Self.stageLeftX,
                    CardOrbitLayout.orbY,
                    0)
            }
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
    private static let surfaceID = "hearth.surface"
    private static let readerID = "hearth.journal-reader"
    private static let mastheadID = "hearth.journal-masthead"

    /// Attachments render in points and the library is measured in metres, so a
    /// label built at a readable font size arrives enormous. This is the one
    /// number that reconciles them.
    private static let labelScale: Float = 0.00055

    /// Where the orb stands when a destination is open. The volume is 0.8m
    /// wide, so this is a little left of the box's own left third -- far enough
    /// to clear a 560pt panel, close enough to still be in the room with it.
    private static let stageLeftX: Float = -0.26


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

        // The centre slot, standing a little forward so it reads as being in
        // front of the stage rather than embedded in it.
        //
        // An attachment that is never added to the content is never rendered,
        // and it fails SILENTLY -- the view is built, the id resolves, and
        // nothing appears. That is what happened here: this block was lost with
        // an unrelated one, and the panel simply did not show.
        if let panel = attachments.entity(for: Self.surfaceID) {
            if panel.parent == nil { content.add(panel) }
            panel.position = SIMD3<Float>(0.09, 0.02, 0.10)
        }

        // An opened journal stands in front of the shelves it came off, and
        // the shelves go dark behind it: a library still visible behind the
        // page you are reading is a library competing with it.
        if let page = attachments.entity(for: Self.readerID) {
            if page.parent == nil { content.add(page) }
            page.position = SIMD3<Float>(0.09, 0.02, 0.14)
        }
        libraryEntity.root.isEnabled = (surface == .journal && reading == nil)

        // Labels ride with the shelves.
        if let masthead = attachments.entity(for: Self.mastheadID) {
            if masthead.parent !== libraryEntity.scrollerEntity {
                masthead.removeFromParent()
                libraryEntity.scrollerEntity.addChild(masthead)
            }
            masthead.position = libraryEntity.mastheadAnchor
            masthead.scale = SIMD3<Float>(repeating: Self.labelScale)
        }
        for room in libraryRooms {
            guard let label = attachments.entity(for: room.id) else { continue }
            if label.parent !== libraryEntity.scrollerEntity {
                label.removeFromParent()
                libraryEntity.scrollerEntity.addChild(label)
            }
            label.position = room.anchor
            label.scale = SIMD3<Float>(repeating: Self.labelScale)
        }
    }

    /// Rebuild the shelves from the house's library.
    private func rebuildLibrary() {
        libraryEntity.apply(heart: library.heart,
                            life: library.life,
                            projects: library.projects,
                            seedlings: library.seedlings,
                            palette: viewModel.personaPalette)
        libraryRooms = libraryEntity.rooms
    }

    /// The first quoted run in the house's reply. See
    /// JournalLibraryEntity.book(matchingTitle:) for why this is temporary.
    private static func firstQuotedTitle(in text: String) -> String {
        for quote in ["\u{201C}", "\"", "'"] {
            let parts = text.components(separatedBy: quote)
            if parts.count >= 2, !parts[1].isEmpty, parts[1].count < 60 {
                return parts[1]
            }
        }
        return ""
    }
}
