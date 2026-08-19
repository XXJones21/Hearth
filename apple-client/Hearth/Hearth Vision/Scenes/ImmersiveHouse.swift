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
    @State private var spawnLocation: SIMD3<Float>?

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

    init(viewModel: ChatViewModel, rig: PersonaRig,
         spawn: simd_float4x4?, onLeave: @escaping () -> Void) {
        self.viewModel = viewModel
        self.rig = rig
        self._cardStore = ObservedObject(wrappedValue: viewModel.cardStore)
        self.spawn = spawn
        self.onLeave = onLeave
    }

    var body: some View {
        RealityView { content, _ in
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
                PersonaDestinationShelf(viewModel: viewModel, active: $surface)
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
            progress: { rig.transitionProgress = $0 }
        )
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
            guard phase == .active, let spawnLocation else { return }
            rig.homePosition = spawnLocation
            rig.rootEntity.position = spawnLocation
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
            entity.position = CardOrbitLayout.offsetFromOrb(index: index, count: cards.count)
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
        if let left = attachments.entity(for: Self.leftShelfID) {
            if left.parent !== anchor { anchor.addChild(left) }
            left.position = SIMD3<Float>(-Self.shelfReach, 0, 0.04)
            left.orientation = simd_quatf(angle: Self.shelfToeIn, axis: SIMD3<Float>(0, 1, 0))
        }
        if let right = attachments.entity(for: Self.rightShelfID) {
            if right.parent !== anchor { anchor.addChild(right) }
            right.position = SIMD3<Float>(Self.shelfReach, 0, 0.04)
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
    }

    private static let liveTextID = "hearth.live-text"
    private static let composerID = "hearth.composer"
    private static let leftShelfID = "hearth.shelf.left"
    private static let rightShelfID = "hearth.shelf.right"
    private static let surfacePanelID = "hearth.panel.surface"
    private static let railPanelID = "hearth.panel.rail"

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
    /// in front of her face.
    private static let shelfReach: Float = 0.30

    /// And how far they turn inward, so a shelf beside her faces the person in
    /// front of her rather than the wall beside them. Fifteen degrees.
    private static let shelfToeIn: Float = .pi / 12

    /// How far out an opened panel stands. Beyond its own shelf, on the same
    /// side, so the thing pressed and the thing opened are in one place.
    private static let panelReach: Float = 0.62

    /// And how high, so a 720pt panel's middle is near eye level rather than
    /// its top edge.
    private static let panelRise: Float = 0.18

    // MARK: - Placement

    /// Where the persona is, in a room.
    ///
    /// The immersive space's origin is where the person was standing when it
    /// opened, at floor level, so these are metres of real room: a metre and a
    /// bit in front, and a height that depends entirely on whether the persona
    /// has a body.
    private func place() {
        // The room's own scale, never the box's. `modelPresentationScale`
        // divides this back out, so a model persona is unaffected by it.
        rig.setRigScale(Self.beadScale)

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
        if spawnLocation == nil { spawnLocation = home }
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
