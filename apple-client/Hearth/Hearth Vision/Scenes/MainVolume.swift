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

    /// Whether the typing bar is up.
    ///
    /// OFF by default. Lifting a model persona 8cm cleared the button shelf and
    /// left her standing in front of the composer, which is the taller of the
    /// two -- and the answer is not to lift her further, because then she
    /// floats above a box she is supposed to be standing in.
    ///
    /// So the bar goes away rather than the persona moving, and Settings' Stage
    /// section brings it back for anyone who wants it. Not a stopgap in the
    /// end: typing is a real way to talk to the house, and which of the two
    /// costs more depends on who is on stage -- a bead the size of a plum
    /// blocks nothing at all.
    ///
    /// The MIC goes with it, which is the cost worth stating: the two live in
    /// one ornament. A pinch on the persona still starts a turn, so voice is
    /// not lost -- but it is now the only way in from the stage.
    ///
    /// `@AppStorage` rather than `ClientPrefs.stageTypingBar` directly, and the
    /// two are the same key: the Settings panel that flips this is an
    /// attachment in THIS window, so the ornament has to answer on the next
    /// frame rather than the next launch.
    @AppStorage(ClientPrefs.stageTypingBarKey) private var textEntryShown = false

    /// The open rail tab, or nil for no rail.
    ///
    /// The desktop's third column, collapsible. It is separate state from
    /// `surface` on purpose: at the desk the rail and the centre view are open
    /// AT THE SAME TIME, and folding them into one selection would make mission
    /// control a destination you leave your work to visit.
    @State private var rail: HouseRailTab?

    /// How far the bookcase sits from the centre slot's own centre. It was
    /// authored at 0.10 against a slot at 0.09, and the difference is what
    /// keeps the shelves' left edge clear of the orb.
    private static let libraryOffsetFromSlot: Float = 0.01

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

    /// EVERYTHING in the box hangs off this, and this is what scales.
    ///
    /// A volumetric window is USER-RESIZABLE, and every number in this file --
    /// where the orb lives, where the library sits, where the clip floor is --
    /// was authored against one assumed box. Resize the window and all of them
    /// are wrong at once, silently: content drifts out of the volume or huddles
    /// in a corner of it, and nothing reports an error.
    ///
    /// So the stage is authored once at `designWidth` and the root carries the
    /// difference. It is the same trick the library already uses for its own
    /// presentation scale, one level up: author at a known size, present at any
    /// size, and let one transform reconcile them.
    @State private var stageRoot = Entity()

    /// The persona's investigation prop: the same library at a tenth scale,
    /// spines turned toward the orb, untouchable.
    ///
    /// A SECOND entity rather than the same one shrunk, because the two are
    /// different objects with different rules -- one is a bookcase a person
    /// browses, the other is scenery the house reads from -- and sharing one
    /// would let a scroll offset or an open book leak between them.
    @State private var propLibrary = JournalLibraryEntity(interactive: false)
    @State private var propVisible = false

    /// Paired AND configured. The app owns this; the volume only renders it.
    let ready: Bool

    /// Hold the persona to leave the box for the room. The app owns the
    /// crossing, because it owns both scenes and the order they open in.
    let onEnterImmersive: () -> Void

    init(viewModel: ChatViewModel, rig: PersonaRig, ready: Bool,
         onEnterImmersive: @escaping () -> Void) {
        self.viewModel = viewModel
        self.rig = rig
        self._cardStore = ObservedObject(wrappedValue: viewModel.cardStore)
        self.ready = ready
        self.onEnterImmersive = onEnterImmersive
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
        GeometryReader3D { geometry in
            stageScene(geometry)
        // A plain pinch starts a voice turn; a two-second hold crosses into the
        // room. One gesture carrying both, because two gestures on one entity
        // race -- see PersonaHold.
        .personaHold(
            target: rig.tapTarget,
            onTap: {
                guard viewModel.connectionStatus == .connected else { return }
                viewModel.toggleListening()
            },
            onHold: onEnterImmersive,
            progress: { rig.transitionProgress = $0 }
        )
        // Belt AND braces, because the two failure modes are different. A
        // scene that was ELIMINATED runs `make` again and adopts her there; a
        // scene that was merely BACKGROUNDED does not, and its update closure
        // may not run until something else invalidates the body. `onAppear`
        // fires in both cases and is the only one that fires the moment the box
        // is back on screen. The call is idempotent -- a pointer comparison and
        // a return.
        .onAppear { adoptPersona() }
        .onChange(of: viewModel.hearthState) { _, state in
            rig.updateState(PersonaState(state))
        }
        // The three persona reads, on edges rather than on every frame. All
        // three still early-return when nothing changed, which is what lets a
        // `persona_config` arriving long after the scene was built land at all.
        .onChange(of: viewModel.personaPalette) { _, palette in
            rig.apply(palette)
        }
        // WHICH persona is on stage, not just what colour they are. Switching to
        // Selene from the status ornament arrives here, and the rig swaps the
        // bead for her model -- travel, tap target and state all keep working,
        // because none of them were ever the bead's. See
        // PersonaRig.apply(visualization:).
        .onChange(of: viewModel.personaVisualization) { _, visualization in
            rig.apply(visualization: visualization)
            if let geometry = visualization.faceGeometry {
                rig.apply(faceGeometry: geometry)
            }
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
                if textEntryShown {
                    ComposerOrnament(viewModel: viewModel)
                }
                HouseShelfOrnament(active: $surface)
            }
        }
        // Mission control, on the right face. An ornament rather than something
        // inside the box for the same reason the bottom shelf is one: it hangs
        // OUTSIDE the volume, so a shelf of three icons costs the stage no
        // width at all and only the opened panel takes any.
        .ornament(attachmentAnchor: .scene(.trailing)) {
            HouseRailOrnament(active: $rail)
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
        // The prop rides the PERFORMANCE, not the turn: it appears when the
        // house starts consulting a journal and goes when it starts talking
        // about what it found. Scale is the whole animation -- nothing, to a
        // tenth, and back -- because a bookcase that faded would read as a
        // ghost, and one that grows reads as being fetched.
        .onChange(of: rig.performingBehavior) { _, name in
            let wanted = (name == "consulting_journal")
            guard wanted != propVisible else { return }
            propVisible = wanted
            propLibrary.root.move(
                to: Transform(scale: SIMD3<Float>(repeating: wanted ? Self.propScale : 0.0001),
                              rotation: propLibrary.root.orientation,
                              translation: propLibrary.root.position),
                relativeTo: propLibrary.root.parent,
                duration: wanted ? 0.55 : 0.35,
                timingFunction: .easeInOut)
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
                    // Divided by the presentation scale so the shelves track
                    // the finger at whatever size the library is shown: the
                    // drag is measured in the world, and `scroll` moves the
                    // library in its own.
                    libraryEntity.scroll = scrollAtGestureStart
                        + Float(value.translation.height) * -0.0024
                        / max(libraryEntity.presentationScale * stageRoot.scale.x, 0.01)
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
        // Opening the rail moves the same two things opening a destination
        // does -- the orb and the centre slot -- so it runs the same code
        // rather than a second copy of it.
        .onChange(of: rail) { _, _ in
            withAnimation(.easeInOut(duration: 0.35)) { slideStage() }
        }
        .onChange(of: surface) { (_, open: HouseSurface?) in
            // Journal fills the centre slot with ENTITIES rather than a panel:
            // its books are three-dimensional and an attachment is a SwiftUI
            // view rendered onto a plane. The orb slides for it like any other
            // destination, because it is one.
            let showingJournal: Bool = open == HouseSurface.journal
            libraryEntity.root.isEnabled = showingJournal
            if open != .journal { reading = nil }
            withAnimation(.easeInOut(duration: 0.35)) { slideStage() }
        }
        }
    }

    /// The RealityView itself, lifted out of `stage`.
    ///
    /// SPLIT FOR THE COMPILER. `stage` is one expression as far as type
    /// inference is concerned -- a RealityView with three closures, then a
    /// dozen chained gestures and `onChange`s -- and it went over the solver's
    /// budget the first time the shared package changed underneath it. The
    /// giveaway was that the reported line MOVED as small edits shifted the
    /// blame around: that is a body which is too large, not a line which is
    /// wrong. Cutting it where the scene ends and the modifiers begin is the
    /// natural seam, and it costs one argument -- the proxy, which only the
    /// update closure reads.
    private func stageScene(_ geometry: GeometryProxy3D) -> some View {
        RealityView { content, _ in
            content.add(stageRoot)
            // Palm-sized and low in the box. The full transform is set rather
            // than just the position because in phase 4 the rig may be
            // returning from the room, carrying a world transform of its own.
            rig.rootEntity.transform = Transform(
                scale: SIMD3<Float>(repeating: Self.beadScale),
                rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                translation: SIMD3<Float>(0, CardOrbitLayout.orbY, 0)
            )
            // Through the rig rather than by writing the scale above alone: the
            // model's size and the anchor's offsets are both fractions OF this,
            // and setting it behind their back leaves them stale. The transform
            // above still sets position and rotation, which nothing derives
            // from.
            rig.setRigScale(Self.beadScale)
            stageRoot.addChild(rig.rootEntity)

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


            // The centre slot's 3D half, hidden until the Journal button asks
            // for it; the orb slides left to make room.
            //
            // A tenth under life size. The geometry stays authored at 1 --
            // that is what lets the persona's prop be the same tree at a tenth
            // -- and this is presentation: a bookcase that fits the box it is
            // shown in without the books stopping being books. It still reaches
            // past the volume's bounds, which is accepted: it can be scrolled
            // and selected, and that is the whole reason to open it.
            //
            // Placed HIGH because shelves hang downward from their own origin.
            // An origin near the middle of the box put the lowest board over
            // the composer and the shelf ornament.
            // 0.9 less a further fifteenth-and-a-half: 0.765, judged on the
            // device rather than derived. The geometry underneath is still
            // authored at life size, so this is only how big the bookcase is
            // shown -- the books have not stopped being 21cm books.
            libraryEntity.presentationScale = 0.765
            // Position first: the travel is measured from where the library
            // sits down to the floor, so the floor has to be set last.

            // 0.36, and the number is the settled one rather than a first
            // guess: 0.32 crowded the composer, 0.40 pushed the masthead into
            // the ceiling, and this is the half-way point that was judged on
            // the device between them.
            libraryEntity.root.position = SIMD3<Float>(0.10, 0.36, 0.02)
            // Nothing draws below this, ever. The composer and the button
            // shelf own the bottom of the box, and a bookcase is not allowed to
            // reach into them: a library that hides the way to talk to the
            // house is a library that has taken the house over.
            //
            // Stated in the VOLUME's units rather than the library's, so the
            // number means what it says -- this is where the ornaments begin.
            libraryEntity.clipBelowInParent = Self.clipFloorY
            libraryEntity.root.isEnabled = false
            stageRoot.addChild(libraryEntity.root)

            // The prop, beside where the orb flies to consult a journal. Spines
            // turned a quarter to face the orb, so the house reads it side-on
            // the way a person reads a shelf. Starts at nothing.
            propLibrary.root.position = SIMD3<Float>(0.30, CardOrbitLayout.orbY + 0.04, 0.02)
            propLibrary.root.orientation = simd_quatf(angle: -.pi / 2,
                                                      axis: SIMD3<Float>(0, 1, 0))
            // A tenth, declared once. The show and hide animate to and from
            // this, so the prop's size lives in one place rather than being
            // repeated in the transform that reveals it.
            propLibrary.presentationScale = Self.propScale
            propLibrary.root.scale = .zero
            stageRoot.addChild(propLibrary.root)

            // A model persona is shown at a fraction of life size in here.
            // Set on the rig rather than folded into the rig root's own scale,
            // because that scale says how big the BEAD is and a person is not
            // sized by a bead. See PersonaRig.modelPresentationScale.
            rig.modelPresentationScale = Self.personaModelScale
            rig.modelVerticalOffset = Self.personaModelLift

            // THE SAME SULIVAN THE ROOM SHOWS. The volume was still lighting
            // the bead while the room burned, which made the crossing a change
            // of PERSONA rather than a change of place -- the one thing the
            // hold gesture is not supposed to mean.
            //
            // The rig's own default is still `.fireflies`, deliberately: it is
            // what a new house shows and what the flame falls back to when its
            // Metal machinery is unavailable. Both hosts opting in explicitly is
            // what keeps that fallback real instead of theoretical.
            //
            // Whether it lands is still the rig's decision -- the fire belongs
            // to a bead, so a switch to Selene puts it out without this line
            // having to know her name.
            rig.effectStyle = .fire
            rig.configure(for: .volumetric)   // billboard halo; bloom is phase 4
            rig.enableInteraction()
            rig.updateState(PersonaState(viewModel.hearthState))
            rig.setConnected(viewModel.connectionAlive)

            // No tick source here any more, and its absence is the point.
            //
            // This host used to own the rig's heartbeat through
            // `content.subscribe(to: SceneEvents.Update.self)`. A subscription
            // belongs to the scene that issued it, so the moment this volume
            // dismisses for the immersive house the rig would stop ticking and
            // freeze in the room with nothing reported. The rig ticks itself
            // now, through a ClosureComponent on its own root -- see that file
            // for the whole argument.
            //
            // The persona reads that closure used to poll sixty times a second
            // moved to `onChange` below, where they fire when the value
            // actually changes. They were polling only because there was no
            // observer to hand.
            rig.apply(viewModel.personaPalette)
            rig.apply(visualization: viewModel.personaVisualization)
            if let geometry = viewModel.personaVisualization.faceGeometry {
                rig.apply(faceGeometry: geometry)
            }
        } update: { content, attachments in
            // The whole reason this is in the update closure and not `make`:
            // resizing the window does not rebuild the scene, it re-runs this.
            let viewBounds = content.convert(geometry.frame(in: .local),
                                             from: .local, to: .scene)
            let scale = Float(viewBounds.extents.x) / Self.designWidth
            // Written to the ENTITY and nowhere else.
            //
            // The first cut also mirrored this into @State so a gesture could
            // read it, which made resizing unresponsive: writing state from
            // inside an update closure invalidates the body, the body re-runs
            // update, and that writes again -- a loop that fires on every frame
            // of a live drag. The entity already knows its own scale, so
            // anything that needs it reads `stageRoot.scale` instead.
            stageRoot.scale = SIMD3<Float>(repeating: scale)
            // THE PERSONA COMES HOME HERE, not in `make`.
            //
            // Closing a window BACKGROUNDS its scene rather than destroying it,
            // so returning from the room re-shows this same RealityView and
            // `make` never runs again. Meanwhile the rig was re-parented into
            // the immersive scene on the way out and is not a child of anything
            // here any more -- which is why the box came back empty with its
            // ornaments still on it.
            //
            // Re-parenting is idempotent and costs a pointer comparison, so it
            // belongs in the closure that always runs rather than the one that
            // runs once.
            adoptPersona()
            layoutAttachments(content: content, attachments: attachments)
        } attachments: {
            ForEach(cardStore.cards) { card in
                Attachment(id: card.id) {
                    StageCard(card: card) { cardStore.dismiss(card.id) }
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
            // ...and only for a persona who HAS a face. A model persona wears
            // her own; billboarding Sulivan's in front of Selene would be two
            // personas on one stage.
            if !rig.hasComputeFace, !rig.modelActive {
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
            // The room labels are GEOMETRY now, inside the library, not
            // attachments here. An attachment renders in points and needed its
            // own scale factor reconciled against the library's metres -- which
            // is why they never appeared, and which would break again the
            // moment the library is presented at two sizes. See
            // JournalLibraryEntity.text.

            // The centre slot, for the four FLAT destinations. Journal is not
            // one: its centre slot is the library's entities, and a panel
            // behind them was a plane standing in front of the shelves.
            if let surface, surface != .journal {
                Attachment(id: Self.surfaceID) {
                    HouseSurfacePanel(viewModel: viewModel,
                                      surface: surface,
                                      width: Self.surfaceWidth(railOpen: rail != nil)) {
                        self.surface = nil
                    }
                }
            }
            // The right rail. Docked rather than floating: it takes width from
            // the centre slot the way the desktop's grid column does, which is
            // what `surfaceWidth` above is answering.
            if let rail {
                Attachment(id: Self.railID) {
                    HouseRailPanel(viewModel: viewModel, tab: rail) {
                        self.rail = nil
                    }
                }
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
    private static let railID = "hearth.rail"

    /// How big a model persona stands in the box, against life size.
    ///
    /// 1.0 is the rig's default and is what phase 4's immersive room will want:
    /// a person in your room should be person-sized. A volumetric window is
    /// 80cm wide, so a life-size Selene filled it and stood through the walls
    /// of it -- 0.4 puts her at about half a metre, a figure on a table.
    private static let personaModelScale: Float = 0.4

    /// How far above the persona's crown the live caption floats, in metres.
    ///
    /// The one number the anchoring still needs, and it is the old absolute
    /// placement restated: the caption sat at `orbY + 0.2` and the bead's crown
    /// is `sphereRadius * 0.22` above `orbY`, so this is what is left over. The
    /// bead's caption therefore does not move at all; Selene's rises to clear
    /// her.
    private static let captionGap: Float = 0.147

    /// And how far she is lifted off it, in metres.
    ///
    /// A figure grounded in the box stands with her legs through the ornaments
    /// along the bottom edge. 16cm clears them, and it arrived in two 8cm
    /// steps for a reason worth remembering: the first cleared the button shelf
    /// and left her in the composer, and then TAKING THE COMPOSER AWAY put the
    /// shelf back over her feet. The two share one VStack, so removing the
    /// taller one moves the other up by its own height. A number measured
    /// against a stack of ornaments has to be re-measured whenever the stack
    /// changes.
    ///
    /// Zero is the rig's default and is what the immersive room wants: nothing
    /// hangs along the bottom of a real floor.
    private static let personaModelLift: Float = 0.16

    /// How big the BEAD is in the box: about 10cm across, a thing you could set
    /// on a table. The room shows the same bead much larger -- see
    /// ImmersiveHouse.beadScale.
    private static let beadScale: Float = 0.22

    /// How big the persona's investigation prop is against life size. Small
    /// enough that its spine lettering is present but unreadable, which is
    /// correct for scenery the house is reading rather than something you are.
    private static let propScale: Float = 0.10

    /// The floor the library may not draw below, in the volume's own space.
    ///
    /// Just above where the composer and the button shelf sit.
    ///
    /// -0.22 was cautious: on the device it cut a whole shelf while leaving a
    /// visible band of unused air between the lowest board and the composer.
    /// The controls are ornaments and ornaments hang OUTSIDE the box, so the
    /// floor only has to clear them by enough to read as separate -- not by
    /// enough to hold them.
    private static let clipFloorY: Float = -0.38

    /// The box every number in this file was authored against.
    ///
    /// It matches `.defaultSize` in HearthVisionApp, and it is the ONLY place
    /// the two have to agree: the stage root reconciles whatever the window
    /// actually is against this.
    private static let designWidth: Float = 0.8

    /// Where the orb stands when a destination is open. The volume is 0.8m
    /// wide, so this is a little left of the box's own left third -- far enough
    /// to clear a 560pt panel, close enough to still be in the room with it.
    private static let stageLeftX: Float = -0.26

    /// And where it stands when the rail is open too.
    ///
    /// Three columns in the width that held two: the centre slot narrows and
    /// slides left, so the orb has to give up its last few centimetres or the
    /// panel's left edge arrives on top of it. This is the only number in the
    /// squeeze that was judged rather than derived -- the rest fall out of the
    /// panel widths below.
    private static let stageLeftXWithRail: Float = -0.30

    /// Where the rail's panel sits: hard against the box's right face.
    ///
    /// A 320pt panel is 0.235m at visionOS's 1360 points to the metre, so its
    /// centre is half of that in from the right edge at +0.4, less a couple of
    /// centimetres so it reads as being IN the box rather than bolted to it.
    private static let stageRightX: Float = 0.26

    /// Where the centre slot sits, with and without the rail beside it.
    private static func surfaceX(railOpen: Bool) -> Float {
        railOpen ? -0.04 : 0.09
    }

    /// How wide the centre slot may be, with and without the rail beside it.
    ///
    /// 440pt against 560pt, and the difference is close to the rail's own
    /// width: this is the desktop's grid doing its arithmetic, not a panel
    /// choosing to be smaller. Every surface in it is a single column of
    /// stacked rows, so narrowing reflows rather than clipping.
    private static func surfaceWidth(railOpen: Bool) -> CGFloat {
        railOpen ? 440 : 560
    }

    /// Put the orb and the centre slot where the current combination of open
    /// things says they go.
    ///
    /// One function because there are two switches -- a destination and a rail
    /// tab -- and four combinations between them. Two independent `onChange`
    /// closures each setting a position would each be right about their own
    /// half and wrong about the other's.
    private func slideStage() {
        let anythingOpen = surface != nil || rail != nil
        rig.homePosition = SIMD3<Float>(
            anythingOpen ? (rail != nil ? Self.stageLeftXWithRail : Self.stageLeftX) : 0,
            CardOrbitLayout.orbY,
            0)
    }


    /// Parent each attachment to the volume and place it. Cards appearing and
    /// expiring under CardStore's TTL show up here as the attachment set
    /// changing, which is why nothing in this file tracks card lifetimes.
    private func layoutAttachments(content: RealityViewContent, attachments: RealityViewAttachments) {
        // Cards and the caption hang off the PERSONA, not off the stage.
        //
        // Reversing a call made on 2026-08-17, and the thing that changed is
        // what is standing on the stage. With a bead the size of a plum,
        // absolute placement was better: the orb never moved far enough to
        // leave its work behind, and prose that slides while you are reading it
        // is worse than prose that sits still. A model persona is half a metre
        // tall, and her head is exactly where the caption was -- so "a bit
        // higher" would be a number that is right for Selene and wrong for
        // Sulivan, twice over the moment a third persona arrives.
        //
        // Anchored, it is one rule: work sits above whoever is there. It is
        // also what phase 4 needs, where the orb genuinely travels.
        let anchor = rig.personaAnchor
        let cards = cardStore.cards
        for (index, card) in cards.enumerated() {
            guard let entity = attachments.entity(for: card.id) else { continue }
            if entity.parent !== anchor { anchor.addChild(entity) }
            // `offsetFromOrb` finally has its caller. It differs from the
            // absolute form only by `orbY`, which is where the anchor now is,
            // so the cards do not move -- they merely stop being nailed down.
            entity.position = CardOrbitLayout.offsetFromOrb(index: index, count: cards.count)
        }

        if let live = attachments.entity(for: Self.liveTextID) {
            if live.parent !== anchor { anchor.addChild(live) }
            // Measured from the top of whoever is on stage rather than from the
            // rig's origin. For the bead this lands exactly where the old
            // absolute number put it; for a figure it clears her head, and for
            // whatever comes next it will not need revisiting.
            live.position = SIMD3<Float>(0, rig.crownHeight + Self.captionGap, -0.02)
        }

        // The fallback face rides just in front of the bead, at the bead's own
        // height. Only ever present when the compute path failed.
        if let face = attachments.entity(for: Self.faceFallbackID) {
            if face.parent !== anchor { anchor.addChild(face) }
            // Dead centre of the bead, which is the anchor's own origin. Only
            // ever present when the compute path failed, and never under a
            // model persona -- she wears her own face.
            face.position = SIMD3<Float>(0, 0, 0.06)
        }

        // The centre slot, standing a little forward so it reads as being in
        // front of the stage rather than embedded in it.
        //
        // An attachment that is never added to the content is never rendered,
        // and it fails SILENTLY -- the view is built, the id resolves, and
        // nothing appears. That is what happened here: this block was lost with
        // an unrelated one, and the panel simply did not show.
        if let panel = attachments.entity(for: Self.surfaceID) {
            if panel.parent !== stageRoot { stageRoot.addChild(panel) }
            panel.position = SIMD3<Float>(Self.surfaceX(railOpen: rail != nil), 0.02, 0.10)
        }

        // The rail, against the right face.
        if let panel = attachments.entity(for: Self.railID) {
            if panel.parent !== stageRoot { stageRoot.addChild(panel) }
            panel.position = SIMD3<Float>(Self.stageRightX, 0.02, 0.10)
        }

        // The library is the Journal destination's centre slot, so it moves
        // with the centre slot. Entities rather than a panel, but the same
        // column: a bookcase that stayed put while every flat surface stepped
        // aside would be the one thing in the box the rail could cover.
        libraryEntity.root.position.x =
            Self.surfaceX(railOpen: rail != nil) + Self.libraryOffsetFromSlot

        // An opened journal stands in front of the shelves it came off, and
        // the shelves go dark behind it: a library still visible behind the
        // page you are reading is a library competing with it.
        if let page = attachments.entity(for: Self.readerID) {
            if page.parent !== stageRoot { stageRoot.addChild(page) }
            page.position = SIMD3<Float>(0.09, 0.02, 0.14)
        }
        libraryEntity.root.isEnabled = (surface == .journal && reading == nil)

    }

    /// Put the persona back in the box, in the box's own terms.
    ///
    /// Everything reset here is something the ROOM changed: it scales the bead
    /// up, it stands the persona somewhere in real space, and it takes the
    /// entity out of this scene entirely. None of that should survive the trip
    /// home, and none of it is reset by the room on its way out -- the room
    /// does not know it is leaving.
    private func adoptPersona() {
        guard rig.rootEntity.parent !== stageRoot else { return }
        stageRoot.addChild(rig.rootEntity)
        rig.setRigScale(Self.beadScale)
        rig.modelPresentationScale = Self.personaModelScale
        rig.modelVerticalOffset = Self.personaModelLift
        rig.configure(for: .volumetric)
        // Facing OUT OF THE BOX, not at you. Billboarding is a room behaviour:
        // there you walk around her, so she has to turn. A volume is a window
        // you are already square to, and a persona swivelling inside it as you
        // lean is a persona who looks nervous.
        rig.facesViewer = false
        rig.workFacesViewer = false
        // A box on a desk gets a quarter of the light -- see EffectBudget. It
        // reaches the real room from here, which was a surprise, but a bead in
        // a window throwing a hearth's worth of light across the room is a lamp
        // somebody would turn off.
        rig.configure(for: .volumetric)
        // The volume has no reconstructed room, so nothing for a proximity
        // spotlight to find. Let go of the room's probe with the rest of it.
        rig.nearbySurfaces = nil
        // And let go of the room's world-tracking provider with it. The rig
        // outlives the room, so a closure left behind here would keep an ARKit
        // session alive for a scene that has closed.
        rig.viewerTransform = nil
        let home = SIMD3<Float>(surface == nil ? 0 : Self.stageLeftX,
                                CardOrbitLayout.orbY, 0)
        rig.homePosition = home
        rig.rootEntity.position = home
    }

    /// Rebuild the shelves from the house's library.
    private func rebuildLibrary() {
        libraryEntity.apply(heart: library.heart,
                            life: library.life,
                            projects: library.projects,
                            seedlings: library.seedlings,
                            palette: viewModel.personaPalette)
        propLibrary.apply(heart: library.heart,
                          life: library.life,
                          projects: library.projects,
                          seedlings: library.seedlings,
                          palette: viewModel.personaPalette)
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

/// One card on the stage, with its dismiss affordance.
///
/// EXTRACTED FOR THE COMPILER, not for reuse, and that is worth saying plainly.
/// `MainVolume.stage` is a RealityView with two closures and a dozen chained
/// gestures, and the whole thing is one expression as far as type inference is
/// concerned. It went over the solver's budget the first time the package
/// changed underneath it -- the error moved from line to line as small edits
/// shifted the blame, which is the signature of a body that is simply too large
/// rather than one line that is wrong. Lifting the card out is the smallest cut
/// that brings it back under, and it costs nothing: a view with two inputs and
/// no state.
private struct StageCard: View {
    let card: UiComponentDescriptor
    let dismiss: () -> Void

    var body: some View {
        DynamicComponent(descriptor: card)
            .frame(maxWidth: 260)
            .padding(12)
            .overlay(alignment: .topTrailing) {
                Button(action: dismiss) {
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
