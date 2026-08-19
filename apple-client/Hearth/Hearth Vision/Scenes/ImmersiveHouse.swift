//
//  ImmersiveHouse.swift
//  Hearth Vision
//
//  The room. Design section 1's expansion: the persona leaves the box and
//  stands in the space you are actually in.
//
//  A DUMB STAGE, like the volume, and for the same reason -- the entity world
//  is owned by the app and this host only places it. What is different is what
//  a room gives that a box could not:
//
//    - The persona is at HER OWN SIZE. `modelPresentationScale` defaults to 1.0
//      and `modelVerticalOffset` to 0, which are the room's answers already, so
//      this host is correct by not copying the volume's 0.4 and 0.16.
//    - There is a floor. A body stands on it; a bead floats above it.
//
//  BLOOM IS OFF, and that is a correction rather than an omission. visionOS
//  blooms only in an immersive space, so this is the one place it could exist --
//  and the first device run showed why it should not exist YET. Valinor's
//  numbers (unbounded, strength 0.9, threshold 0.5) were tuned against Valinor's
//  orb; against a cream bead they blow the whole persona into a white disc and
//  wash the face off it, which is exactly the "washed out eyes" this project
//  already fixed once for a different reason. The room now presents the persona
//  identically to the box -- same entity, same halo, same face -- and bloom
//  becomes its own tuning step alongside the fire in phase 4.5, where the look
//  is being redesigned anyway.
//
//  WORK COMES WITH HER, and it has to be rebuilt here rather than carried. The
//  cards and the caption hang off `personaAnchor`, which travels -- but a
//  RealityView's ATTACHMENTS belong to the view that declared them, so the
//  volume's attachment entities died with the volume's scene. The room declares
//  its own and hangs them on the same anchor at the same offsets, so the layout
//  is shared even though the hosting is not.
//
//  The unification is `ViewAttachmentComponent`, which puts a SwiftUI view on an
//  ENTITY as a component rather than through a view's attachments closure --
//  which would survive re-hosting outright and is what the persona-mounted
//  shelves want. That is the next increment; this is the smaller change that
//  makes a turn work in the room today.
//
//  WHAT THIS STILL DOES NOT DO: the room's own light (phase 4.5), and world
//  reconstruction so a panel pulled off a shelf can be left on a real table.
//  Panels open beside the persona for now and travel with her, which is right
//  until there is somewhere real to put them down.
//

import SwiftUI
import RealityKit
import HearthCore
import HearthUI
import HearthSpatial

/// Somewhere for the room to remember a placement without telling SwiftUI.
///
/// See `ImmersiveHouse.placement` for why this is a class.
@MainActor
private final class RoomPlacement {
    var spawn: SIMD3<Float>?
}

struct ImmersiveHouse: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var rig: PersonaRig
    @ObservedObject private var cardStore: CardStore

    /// Where the persona was standing, in this space's own coordinates, at the
    /// moment of crossing. Nil until the app has read it.
    ///
    /// The room does NOT take the rig until this arrives. That is the whole
    /// sequencing: the read has to happen while the rig is still in the volume
    /// and both scenes are open, so a `make` closure that grabbed the entity on
    /// appear would take it away a frame before it could be measured.
    let spawn: simd_float4x4?

    /// Hold the persona to go back to the box.
    let onLeave: () -> Void

    /// True from the instant a departure begins until this view is gone.
    ///
    /// THE RACE THIS EXISTS FOR. An app cannot close its last scene, so leaving
    /// has to open the volume BEFORE dismissing this space -- which means both
    /// are alive for a moment, and in that moment the volume adopts the rig out
    /// of here. Without this flag the update closure below sees the rig gone,
    /// decides it must have been lost, and takes it straight back. The space
    /// then closes with the persona inside it and the box is empty, which is
    /// the missing-persona bug wearing its second face.
    @State private var releasing = false

    /// Where the persona was first put in this room.
    ///
    /// Kept so she can be found again. Recentring the world -- holding the
    /// Digital Crown -- moves the origin out from under everything placed in
    /// it, and a persona who was three metres away is now three metres from
    /// somewhere else. Re-applying this puts her back where the room started
    /// rather than leaving her somewhere behind a wall.
    ///
    /// A REFERENCE type, and that is not a style choice. This is written by
    /// `place()`, which runs inside the RealityView's update closure, and
    /// writing a `@State` value there is "Modifying state during view update,
    /// this will cause undefined behavior" -- SwiftUI's words. It is also how
    /// the room came up EMPTY: the write invalidated the body mid-update, and
    /// the add that should have followed it did not reliably land. Mutating a
    /// property of a held object is not a state change, so the closure can
    /// remember something without telling SwiftUI it has.
    @State private var placement = RoomPlacement()

    @Environment(\.scenePhase) private var scenePhase

    /// Typing, for the times speaking aloud is not available.
    ///
    /// The same preference the box uses, and the same key -- Settings' Stage
    /// section flips both. It reads differently here because a room reads
    /// differently: a headset has no keyboard and no controller, so speech is
    /// the way in and typing is the ACCESSIBILITY path rather than the
    /// convenience one. Off, the tap starts a turn. On, the tap raises a
    /// composer with the keyboard already focused, which is the same gesture
    /// meaning the same thing -- "I want to say something" -- through whichever
    /// channel is available to the person doing it.
    @AppStorage(ClientPrefs.stageTypingBarKey) private var typingEnabled = false

    /// Up only while someone is typing. A composer permanently in front of the
    /// persona in a room is a control standing between you and her.
    @State private var composing = false

    /// The open destination and the open rail tab. Separate state, because at
    /// the desk both are open at once and folding them into one selection would
    /// make mission control a place you leave your work to visit.
    @State private var surface: HouseSurface?
    @State private var rail: HouseRailTab?

    /// The bookcase, once someone has pulled it off the shelf.
    ///
    /// PARENTED TO THE ROOM, not to the persona, and that is the difference
    /// between this and everything else the shelves open. A panel is work she
    /// is showing you and belongs beside her; a bookcase is FURNITURE. You put
    /// it somewhere, you walk to it, and it is still there when she has moved
    /// across the room. It is also why `presentationScale` exists at all: the
    /// geometry has always been authored at life size, the box showed it at
    /// 0.765, and a real floor shows it at 1.
    @State private var library = JournalLibraryEntity()
    @StateObject private var libraryData = JournalLibrary()
    @State private var libraryPlaced = false

    /// Where the bookcase STANDS, as opposed to what it looks like.
    ///
    /// An empty root, and the same split the persona already has: `rootEntity`
    /// is where she is, `modelHost` and `personaAnchor` are how big she is and
    /// what hangs off her. A gesture moves the placement; the presentation is
    /// nobody's business but the object's.
    ///
    /// Without it every gesture writes `library.root` -- which is where the
    /// entity keeps `presentationScale`, as its own `scale`. A pinch-to-scale
    /// would then be writing the same field the library writes whenever its
    /// presentation changes, and whichever wrote last would win. The floor
    /// offset had the same problem in slower motion: `standLibraryOnFloor`
    /// wrote a position the entity also considers its own.
    ///
    /// So: the placement root sits ON THE FLOOR at the spot the bookcase
    /// occupies, the library hangs inside it lifted by its own height, and the
    /// close button hangs beside it unaffected by how big the bookcase is.
    /// Anchoring anchors THIS -- one transform, one meaning. See PlacedObject
    /// for the pattern, which every placed thing shares now.
    @State private var libraryPlacement = PlacedObject(named: "LibraryPlacement")

    /// And the opened book, which is placed SEPARATELY from the shelf it came
    /// off.
    ///
    /// A reader welded beside the bookcase is only readable if the bookcase is
    /// within reading distance, so consulting one book meant dragging the whole
    /// library across the room and putting it back. Pulling a book off a shelf
    /// and bringing it to your desk is the real gesture, and it needs the book
    /// to be its own placed thing. It returns to the shelf's side when closed,
    /// so the next one opens somewhere known rather than wherever the last one
    /// was abandoned.
    @State private var readerPlacement = PlacedObject(named: "ReaderPlacement")

    /// What the room remembers about where things were left.
    @StateObject private var anchors = RoomAnchors()

    /// The journal being read, or nil for the shelves.
    ///
    /// The books were pinchable from the moment the bookcase existed -- they
    /// carry collision and a hover effect of their own, which is why they lit
    /// up -- and nothing was listening. Highlighting is the entity saying it
    /// can be touched; opening is the host's job, and the room had not been
    /// given it.
    @State private var reading: JournalBook?

    init(viewModel: ChatViewModel, rig: PersonaRig,
         spawn: simd_float4x4?, onLeave: @escaping () -> Void) {
        self.viewModel = viewModel
        self.rig = rig
        self._cardStore = ObservedObject(wrappedValue: viewModel.cardStore)
        self.spawn = spawn
        self.onLeave = onLeave
    }

    /// The scene itself, plus the two gestures aimed at things inside it.
    ///
    /// Split from `body` because the whole view in one expression stopped
    /// type-checking in reasonable time -- SwiftUI's modifier chains build one
    /// enormous generic type, and this one had grown a RealityView, its
    /// attachments, two gestures and eight observers. Two named halves cost
    /// nothing at runtime and let the compiler finish.
    private var stage: some View {
        RealityView { content, _ in
            // ADDED HERE as well as in `update`, and the belt matters more than
            // the braces. The update closure only runs when the body is
            // invalidated, and the room's one guaranteed invalidation -- the
            // spawn transform arriving -- does not happen when that transform
            // comes back nil. Which is exactly the case where the persona is
            // most needed and was least present.
            place()
            content.add(rig.rootEntity)

            // `.volumetric`, in a room, deliberately: that mode keeps the
            // billboard halo, and the halo is what the bead's glow IS until
            // bloom is tuned. Switching to `.immersive` here took the halo away
            // and put an untuned bloom in its place, which is how the persona
            // arrived in the room looking like a different persona.
            rig.configure(for: .volumetric)
            rig.enableInteraction()
            rig.updateState(PersonaState(viewModel.hearthState))
            rig.setConnected(viewModel.connectionAlive)
            rig.apply(viewModel.personaPalette)
            rig.apply(visualization: viewModel.personaVisualization)
            if let geometry = viewModel.personaVisualization.faceGeometry {
                rig.apply(faceGeometry: geometry)
            }
            // No tick subscription. The rig carries its own ClosureComponent and
            // RealityKit runs the system in whatever scene the entity is in,
            // which is the whole reason this handover is a re-parent rather than
            // a rebuild.
        } update: { content, attachments in
            // `releasing` is the whole guard: on the way out the volume has
            // already taken her, and taking her back would close this space
            // with the persona still in it.
            if !releasing, !content.entities.contains(rig.rootEntity) {
                place()
                content.add(rig.rootEntity)
            }
            // The bookcase belongs to the room, so it is added to the room
            // rather than hung on the persona.
            if libraryPlaced, !content.entities.contains(libraryPlacement.root) {
                content.add(libraryPlacement.root)
                standLibraryOnFloor()
            }
            // The reader is the room's, not the bookcase's, so it is added to
            // the room -- which is what lets it be carried away from the shelf.
            if reading != nil, !content.entities.contains(readerPlacement.root) {
                content.add(readerPlacement.root)
            }
            layoutWork(attachments: attachments)
        } attachments: {
            // The same cards the box shows, declared again because attachments
            // belong to the view that declares them. Their PLACEMENT is shared:
            // `CardOrbitLayout` is the one answer to where work sits.
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
            Attachment(id: Self.liveTextID) {
                LiveText(viewModel: viewModel)
            }
            if composing {
                Attachment(id: Self.composerID) {
                    ComposerOrnament(viewModel: viewModel,
                                     autoFocus: true,
                                     onDismiss: { composing = false })
                }
            }
            // The controls, which in a room belong to the persona rather than
            // to a window she no longer has. See PersonaShelves.
            Attachment(id: Self.leftShelfID) {
                PersonaDestinationShelf(viewModel: viewModel,
                                        active: $surface,
                                        onSpawnLibrary: placeLibrary,
                                        libraryPlaced: libraryPlaced)
            }
            // The way to put the bookcase away again, beside it rather than on
            // it: a control ON a shelf of books would be one more thing among
            // the spines, and the one thing there that is not a book.
            // An opened journal, standing beside the bookcase it came off.
            // JournalBookView unchanged -- the shelf is new, what is written in
            // a journal is not.
            if let reading {
                Attachment(id: Self.readerID) {
                    VStack(spacing: 0) {
                        HStack {
                            Button {
                                openReader(nil)
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
            if libraryPlaced {
                Attachment(id: Self.libraryCloseID) {
                    Button {
                        removeLibrary()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .glassBackgroundEffect()
                    .accessibilityLabel("Put the library away")
                }
            }
            Attachment(id: Self.rightShelfID) {
                PersonaRailShelf(active: $rail)
            }
            if let surface, surface != .journal {
                Attachment(id: Self.surfacePanelID) {
                    HouseSurfacePanel(viewModel: viewModel, surface: surface) {
                        self.surface = nil
                    }
                }
            }
            if let rail {
                Attachment(id: Self.railPanelID) {
                    HouseRailPanel(viewModel: viewModel, tab: rail) {
                        self.rail = nil
                    }
                }
            }
        }
        .personaHold(
            target: rig.tapTarget,
            onTap: {
                guard viewModel.connectionStatus == .connected else { return }
                guard !typingEnabled else {
                    // Not "as well as": INSTEAD OF. Someone typing because they
                    // cannot speak should not have a live microphone open while
                    // they do it.
                    composing = true
                    return
                }
                viewModel.toggleListening()
            },
            onHold: {
                releasing = true
                onLeave()
            },
            // Drag her somewhere else in the room. Clamped so she cannot be
            // pushed through the floor, which in a room is a real place rather
            // than an abstraction.
            onDrag: { position in
                var home = position
                home.y = max(home.y, floorClearance)
                rig.homePosition = home
                rig.rootEntity.position = home
            },
            onDragEnded: {
                anchors.remember(.persona, at: rig.rootEntity.transformMatrix(relativeTo: nil))
            },
            progress: { rig.transitionProgress = $0 }
        )
    }

    var body: some View {
        stage
        .onChange(of: viewModel.hearthState) { _, state in
            rig.updateState(PersonaState(state))
        }
        .onChange(of: viewModel.connectionAlive) { _, alive in
            rig.setConnected(alive)
        }
        .onChange(of: viewModel.ttsAmplitude) { _, level in
            rig.audioLevel = level
        }
        .onChange(of: viewModel.micLevel) { _, level in
            if viewModel.isListening { rig.audioLevel = level }
        }
        .onChange(of: viewModel.personaPalette) { _, palette in
            rig.apply(palette)
        }
        // A recentre does not announce itself, but it does take the app through
        // a phase change, and coming back to `.active` is the one moment worth
        // checking whether the persona is still somewhere findable.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let home = placement.spawn else { return }
            rig.homePosition = home
            rig.rootEntity.position = home
        }
        // The bookcase is a room object, so its own drag is its own gesture --
        // it does not travel with the persona and must not be moved by her.
        .gesture(
            DragGesture()
                .targetedToEntity(library.dragSurface)
                .onChanged { value in
                    guard libraryPlaced else { return }
                    // Across the floor only. A bookcase you can lift into the
                    // air is a bookcase you can lose above the ceiling, and its
                    // height is already right -- it is standing on the floor.
                    libraryPlacement.drag(
                        to: SIMD3<Float>(value.convert(value.location3D,
                                                       from: .local, to: .scene)),
                        onFloor: true)
                }
                .onEnded { _ in
                    libraryPlacement.endGesture()
                    // Anchored where it was LET GO, not where it was grabbed.
                    anchors.remember(.library, at: libraryPlacement.worldTransform)
                }
        )
        // And the book you are reading, carried anywhere you like -- including
        // up, because bringing a page closer usually means bringing it to eye
        // level as well as toward you.
        .simultaneousGesture(
            DragGesture()
                // The HANDLE, not the root: a root has no collision shape, and
                // a gesture reaches an entity through one. See
                // PlacedObject.addGrabHandle.
                .targetedToEntity(readerPlacement.grabHandle ?? readerPlacement.root)
                .onChanged { value in
                    guard reading != nil else { return }
                    readerPlacement.drag(
                        to: SIMD3<Float>(value.convert(value.location3D,
                                                       from: .local, to: .scene)),
                        onFloor: false)
                }
                .onEnded { _ in readerPlacement.endGesture() }
        )
        // Pinch a spine to read it. Targeted at the library's whole subtree
        // because the hit lands on a book, and `book(for:)` is what turns an
        // entity back into a journal -- the same call the box makes. A hit on
        // anything else in the tree resolves to nil and closes the reader,
        // which is the same gesture meaning "not that one".
        //
        // Simultaneous with the bookcase's own drag rather than racing it:
        // they target different entities, and declaring that plainly is
        // cheaper than finding out which one SwiftUI would have preferred.
        .simultaneousGesture(
            SpatialTapGesture()
                .targetedToEntity(library.root)
                .onEnded { value in
                    guard libraryPlaced else { return }
                    openReader(library.book(for: value.entity))
                }
        )
        .task { await anchors.run() }
        // Restoring is not a startup step, because an anchor arrives when ARKit
        // recognises the place -- which may be seconds after the room opens, or
        // never if you are somewhere else. So it is applied whenever it turns
        // up, and until then everything stands where it spawned.
        .onChange(of: anchors.placements) { _, placements in
            restore(placements)
        }
        .task {
            await libraryData.load()
            library.apply(heart: libraryData.heart,
                          life: libraryData.life,
                          projects: libraryData.projects,
                          seedlings: libraryData.seedlings,
                          palette: viewModel.personaPalette)
            // AND AGAIN, once there are books to measure.
            //
            // A restored anchor can arrive before the library has been fetched
            // -- ARKit recognises a room in a moment and the house takes longer
            // than that -- and an empty bookcase has no height to stand it by.
            // So the lift is re-applied when the shelves are actually there,
            // which is why it had to be idempotent: measuring a bookcase that
            // already rests on the floor subtracts nothing.
            standLibraryOnFloor()
        }
        .onChange(of: viewModel.personaVisualization) { _, visualization in
            rig.apply(visualization: visualization)
            if let geometry = visualization.faceGeometry {
                rig.apply(faceGeometry: geometry)
            }
            // Her size changed, so where she stands did too.
            place()
        }
    }

    /// Hang the cards and the caption on the persona, exactly as the box does.
    private func layoutWork(attachments: RealityViewAttachments) {
        let anchor = rig.personaAnchor
        let cards = cardStore.cards
        for (index, card) in cards.enumerated() {
            guard let entity = attachments.entity(for: card.id) else { continue }
            if entity.parent !== anchor { anchor.addChild(entity) }
            // Pushed clear of her for the same reason the shelves are: a card's
            // dismiss button inside a life-size persona's collision box is a
            // button that cannot be pressed. `CardOrbitLayout` decides the
            // column; how far out that column has to start is a fact about who
            // is standing there.
            var offset = CardOrbitLayout.offsetFromOrb(index: index, count: cards.count)
            offset.x = -max(abs(offset.x), rig.halfWidth + Self.shelfClearance)
            entity.position = offset
        }
        if let live = attachments.entity(for: Self.liveTextID) {
            if live.parent !== anchor { anchor.addChild(live) }
            live.position = SIMD3<Float>(0, rig.crownHeight + Self.captionGap, -0.02)
        }
        // Below her and a little forward, where a person's own hands are: the
        // caption is something she says and sits above her, the composer is
        // something you say and sits where you would hold it.
        if let composer = attachments.entity(for: Self.composerID) {
            if composer.parent !== anchor { anchor.addChild(composer) }
            composer.position = SIMD3<Float>(0, -(rig.crownHeight + Self.composerDrop), 0.12)
        }

        // The shelves, either side of her and turned slightly inward so they
        // face the person standing in front rather than the wall beside them.
        // CLEAR OF HER, not merely beside her. A persona's collision box spans
        // her whole body, so a shelf inside that span is not just overlapping
        // -- it is unreachable, because every pinch aimed at it lands on her.
        // 30cm is a comfortable reach from a bead the size of a plum and is
        // INSIDE a life-size person, which is exactly why neither shelf
        // responded when Selene was on stage.
        let reach = max(Self.shelfReach, rig.halfWidth + Self.shelfClearance)
        if let left = attachments.entity(for: Self.leftShelfID) {
            if left.parent !== anchor { anchor.addChild(left) }
            left.position = SIMD3<Float>(-reach, 0, 0.04)
            left.orientation = simd_quatf(angle: Self.shelfToeIn, axis: SIMD3<Float>(0, 1, 0))
        }
        if let right = attachments.entity(for: Self.rightShelfID) {
            if right.parent !== anchor { anchor.addChild(right) }
            right.position = SIMD3<Float>(reach, 0, 0.04)
            right.orientation = simd_quatf(angle: -Self.shelfToeIn, axis: SIMD3<Float>(0, 1, 0))
        }

        // An opened panel stands beyond its own shelf, on the same side, so the
        // thing you pressed and the thing that opened are in one place.
        if let panel = attachments.entity(for: Self.surfacePanelID) {
            if panel.parent !== anchor { anchor.addChild(panel) }
            panel.position = SIMD3<Float>(-Self.panelReach, Self.panelRise, 0.10)
        }
        if let panel = attachments.entity(for: Self.railPanelID) {
            if panel.parent !== anchor { anchor.addChild(panel) }
            panel.position = SIMD3<Float>(Self.panelReach, Self.panelRise, 0.10)
        }

        // The bookcase's close button rides on the BOOKCASE, so it goes where
        // the bookcase goes rather than staying where it was first put.
        // On the PLACEMENT, not on the library: a control that scaled with the
        // bookcase would be illegible on a small one and enormous on a large
        // one, and it is not part of the furniture -- it is how you put the
        // furniture away.
        if let close = attachments.entity(for: Self.libraryCloseID) {
            if close.parent !== libraryPlacement.root { libraryPlacement.root.addChild(close) }
            close.position = SIMD3<Float>(-Self.libraryCloseReach, Self.libraryCloseRise, 0.1)
        }

        // The reader hangs at its own placement's origin, because the
        // PLACEMENT is what moves. Where that placement starts is decided when
        // the book is opened -- see `openReader`.
        if let page = attachments.entity(for: Self.readerID) {
            if page.parent !== readerPlacement.root { readerPlacement.root.addChild(page) }
            page.position = .zero
        }
    }

    /// Stand the bookcase in the room, life size, on the floor.
    private func placeLibrary() {
        guard !libraryPlaced else { return }
        libraryPlaced = true

        // Life size. Not a number this host picked -- the geometry has always
        // been authored at 21cm books and a real bookcase is what that IS.
        library.presentationScale = 1

        // NO CLIP AND NO SCROLL, and one nil does both. Clipping existed
        // because a volume has a composer along its bottom edge; the drag
        // existed because a bookcase taller than the box could not otherwise be
        // seen. A bookcase standing on a real floor needs neither -- you walk
        // to it, and you look up.
        library.clipBelowInParent = nil

        // The library hangs inside the placement; the placement is what stands
        // in the room.
        if library.root.parent !== libraryPlacement.root {
            libraryPlacement.root.addChild(library.root)
        }
        library.root.isEnabled = true

        // Beside the persona, on the floor. The HEIGHT of the library within
        // the placement is set once it is in the scene and can be measured --
        // see `standLibraryOnFloor`.
        let home = rig.rootEntity.position
        libraryPlacement.spawn(at: SIMD3<Float>(home.x - Self.libraryReach, 0, home.z))
    }

    /// Open a book, or close the one that is open.
    ///
    /// The reader starts beside the bookcase -- where it always appeared -- and
    /// is then yours to bring closer. Closing it sends the placement home, so
    /// the next book opens at the shelf rather than wherever the last one was
    /// put down.
    private func openReader(_ book: JournalBook?) {
        reading = book
        guard book != nil else {
            readerPlacement.returnHome()
            return
        }
        let shelf = libraryPlacement.root.position
        readerPlacement.spawn(at: SIMD3<Float>(shelf.x + Self.readerReach,
                                               Self.readerRise,
                                               shelf.z + 0.14))
        // Sized to the panel it hangs under: 420 x 560 points is 0.31 x 0.41
        // metres at visionOS's 1360 points to the metre, and the bar is a good
        // deal narrower than that so it reads as a handle.
        readerPlacement.addGrabHandle(width: Self.readerHandleWidth,
                                      drop: Self.readerHandleDrop)
    }

    /// Lift the bookcase until its lowest shelf rests on the floor.
    ///
    /// Its root is the TOP of the bookcase, not the bottom: shelves are placed
    /// at `-topDrop - row * shelfPitch`, so the whole thing hangs DOWNWARD from
    /// the origin. Putting that origin at y=0 -- the floor, since the immersive
    /// space's origin is the point on the ground below you -- therefore buried
    /// the entire bookcase under the floorboards with only its masthead
    /// showing.
    ///
    /// Measured rather than derived, for the same reason the model's framing is
    /// and the book titles' centring is: the height depends on how many rooms
    /// the house has, how many books are in them, and the presentation scale,
    /// and any formula reproducing that here would be a second copy of
    /// arithmetic the entity already does.
    /// Lift the bookcase until its lowest shelf rests on the placement.
    ///
    /// Idempotent, and that is what lets it be called from three places: when
    /// the bookcase is first added, when the books finally arrive, and when an
    /// anchor puts it back. A bookcase already resting on the floor measures a
    /// `min.y` of zero and is moved by nothing.
    private func standLibraryOnFloor() {
        guard libraryPlaced else { return }
        // Measured in the PLACEMENT's space and corrected within it, so the
        // placement root keeps meaning "the spot on the floor this bookcase
        // occupies" no matter how tall the bookcase turns out to be.
        let bounds = library.root.visualBounds(relativeTo: libraryPlacement.root)
        guard bounds.extents.y > 0.0001 else { return }
        library.root.position.y -= bounds.min.y
    }

    private func removeLibrary() {
        libraryPlaced = false
        openReader(nil)
        libraryPlacement.root.removeFromParent()
        readerPlacement.root.removeFromParent()
        libraryPlacement.endGesture()
        // Put away, not merely moved: the room should not stand it back up
        // tomorrow because it remembers a wall it used to lean against.
        anchors.forget(.library)
    }

    /// Put back what the room remembers, whenever ARKit gets round to saying so.
    ///
    /// The bookcase is STOOD UP by its own anchor, not merely repositioned: a
    /// thing you left against a wall should be against that wall when you come
    /// back, without being pulled off the shelf again first. That is the whole
    /// point of anchoring it.
    private func restore(_ placements: [RoomSlot: simd_float4x4]) {
        if let t = placements[.persona] {
            let home = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            rig.homePosition = home
            rig.rootEntity.position = home
        }
        if let t = placements[.library] {
            if !libraryPlaced { placeLibrary() }
            libraryPlacement.root.setTransformMatrix(t, relativeTo: nil)
            libraryPlacement.spawn(at: libraryPlacement.root.position,
                                   facing: libraryPlacement.root.orientation)
            // The anchor remembers where the bookcase STANDS -- the placement
            // root, on the floor. How far the shelves hang below that root is
            // the library's own business and is re-derived here, because
            // nothing about the anchor knows how many books arrived.
            standLibraryOnFloor()
        }
    }

    private static let liveTextID = "hearth.live-text"
    private static let composerID = "hearth.composer"
    private static let leftShelfID = "hearth.shelf.left"
    private static let rightShelfID = "hearth.shelf.right"
    private static let surfacePanelID = "hearth.panel.surface"
    private static let railPanelID = "hearth.panel.rail"
    private static let libraryCloseID = "hearth.library.close"
    private static let readerID = "hearth.journal-reader"

    /// The caption's clearance above the persona's crown. The volume's number,
    /// and it means the same thing here because both measure from the same
    /// place -- which is the point of measuring from the crown at all.
    private static let captionGap: Float = 0.147

    /// How far below the persona's underside the composer hangs. Measured from
    /// her rather than from the floor, for the same reason the caption is: it
    /// then means the same thing whoever is standing there.
    private static let composerDrop: Float = 0.12

    /// How far to each side the shelves sit, in metres. The operator's number,
    /// judged as a reach: close enough to belong to her, far enough not to be
    /// in front of her face. A FLOOR rather than the answer -- see
    /// `shelfClearance`.
    private static let shelfReach: Float = 0.30

    /// And how far outside her the shelves must stay whatever size she is.
    /// A hand's width past the edge of the persona, so a shelf beside a
    /// life-size figure is beside her rather than inside her.
    private static let shelfClearance: Float = 0.12

    /// And how far they turn inward, so a shelf beside her faces the person in
    /// front of her rather than the wall beside them. Fifteen degrees.
    private static let shelfToeIn: Float = .pi / 12

    /// How far out an opened panel stands. Beyond its own shelf, on the same
    /// side, so the thing pressed and the thing opened are in one place.
    private static let panelReach: Float = 0.62

    /// And how high, so a 720pt panel's middle is near eye level rather than
    /// its top edge.
    private static let panelRise: Float = 0.18

    /// How far to the persona's left the bookcase first stands. Far enough to
    /// be a separate object rather than something she is holding; near enough
    /// that it arrives in view rather than behind you.
    private static let libraryReach: Float = 1.1

    /// Where the bookcase's close button sits: off its left edge, at reading
    /// height, so it is beside the shelves rather than among the spines.
    private static let libraryCloseReach: Float = 0.5
    private static let libraryCloseRise: Float = 1.3

    /// Where an opened journal stands: off the bookcase's other side, so the
    /// shelves stay visible beside what you are reading rather than behind it,
    /// and at a height you would hold a book at.
    private static let readerReach: Float = 0.62
    private static let readerRise: Float = 1.25

    /// The reader's grab bar: about two thirds the panel's width, hanging just
    /// under its lower edge. The panel is 560pt tall, which is 0.41m, so half
    /// of it plus a little clearance is where the bar goes.
    private static let readerHandleWidth: Float = 0.20
    private static let readerHandleDrop: Float = 0.24

    // MARK: - Placement

    /// Where the persona is, in a room.
    ///
    /// The immersive space's origin is where the person was standing when it
    /// opened, at floor level, so these are metres of real room: a metre and a
    /// bit in front, and a height that depends entirely on whether the persona
    /// has a body.
    private func place() {
        // The room's own numbers, and ALL of them, stated rather than assumed.
        //
        // The rig is shared and the box changed it: 0.4 of life size, lifted
        // 16cm to clear ornaments that do not exist here. Those are facts about
        // a box with controls along its bottom edge, and leaving them in place
        // is why Selene arrived in the room at less than half her height. The
        // rig's defaults are the room's answers, but a default is only the
        // answer until something else has set it.
        rig.setRigScale(Self.beadScale)
        rig.modelPresentationScale = 1
        rig.modelVerticalOffset = 0

        // WHERE she stood in the box, if the crossing measured it, and a
        // sensible spot in front of the person if it did not -- the first run
        // after a launch, or a capture that could not be taken.
        //
        // Only X and Z are carried. The captured Y is where she was inside a
        // floating box, which is not where she belongs on a real floor: a body
        // has to stand on it and a bead has its own resting height. Height is
        // the room's rule; the SPOT is hers.
        let captured = spawn.map { SIMD3<Float>($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
        let home = SIMD3<Float>(captured?.x ?? 0,
                                originHeight(carrying: captured?.y),
                                captured?.z ?? -Self.distance)
        rig.homePosition = home
        rig.rootEntity.position = home
        // Remembered, not recomputed: dragging her somewhere else should not
        // change where "back to the start" means.
        if placement.spawn == nil { placement.spawn = home }
    }

    /// How high the rig's ORIGIN sits above the floor.
    ///
    /// Two rules, because there are two kinds of persona and no single number
    /// serves both. A model is centred on the rig's origin by its own framing
    /// pass, so putting the origin at `crownHeight` -- half her height -- lands
    /// her feet on the floor; a captured height would leave her standing in the
    /// air where a floating window happened to be. A bead has no feet, so it
    /// keeps the height it was crossed at when there is one, and floats at
    /// roughly chest height when there is not.
    private func originHeight(carrying captured: Float?) -> Float {
        guard !rig.isCorporeal else { return rig.crownHeight }
        // A box set on a low table would put the bead near the floor; clamp so
        // it stays somewhere a conversation happens.
        guard let captured else { return Self.beadHeight }
        return min(max(captured, Self.beadFloor), Self.beadCeiling)
    }

    /// The lowest the persona may be dragged, so a bead cannot be pushed into
    /// the carpet and a body cannot be sunk through the floorboards. Valinor's
    /// number for the same gesture; a body needs its own half-height on top.
    private var floorClearance: Float {
        rig.isCorporeal ? rig.crownHeight : Self.beadFloor
    }

    /// How far in front of where the person was standing.
    private static let distance: Float = 1.35

    /// A bead's resting height, roughly chest-high on a standing adult. Used
    /// when the crossing carried no height of its own.
    private static let beadHeight: Float = 1.25

    /// And the range a carried height is allowed to land in. A volume can be
    /// dragged to the floor or above head height, and neither is where a
    /// conversation happens.
    private static let beadFloor: Float = 0.7
    private static let beadCeiling: Float = 1.9

    /// How big the BEAD is in a room.
    ///
    /// The volume shows it at 0.22, which is a bead you could set on a table --
    /// about 10cm across. A room is not a table and the same number reads as a
    /// marble lost on the carpet. 0.5 is roughly a grapefruit, and it is a first
    /// guess rather than a judged number: this is the first thing to change on
    /// the device. A model persona is unaffected -- `modelPresentationScale`
    /// divides this back out precisely so her size is a fact about her.
    private static let beadScale: Float = 0.5

}
