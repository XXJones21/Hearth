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
//    - Bloom is REAL. visionOS does not bloom in a volume or the shared space at
//      all -- the volume's billboard halo exists because of that, not as a
//      preference -- so the one place the orb can actually glow is here.
//    - There is a floor. A body stands on it; a bead floats above it.
//
//  WHAT THIS DOES NOT YET DO, and each is written down rather than forgotten:
//  the persona-mounted control shelves (phase 4, next increment), the room's
//  own light (phase 4.5), world reconstruction so panels can be set on real
//  tables, and preserving the persona's exact physical spot across the
//  crossing. On that last one -- Valinor composes the captured transform
//  through `content.transform(from: .immersiveSpace, to: .scene)`, whose return
//  type is a DOUBLE-precision `AffineTransform3D` and whose mis-assumption is
//  risk point 1 in its own handoff. Placing her in front of the person is the
//  honest first version; matching the spot is a refinement with a known trap in
//  it.
//

import SwiftUI
import RealityKit
import HearthCore
import HearthUI
import HearthSpatial

struct ImmersiveHouse: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var rig: PersonaRig

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

    var body: some View {
        RealityView { content in
            rig.configure(for: .immersive)   // the billboard halo goes; real bloom takes over
            applyBloom()
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
        } update: { content in
            guard rig.rootEntity.parent == nil || !content.entities.contains(rig.rootEntity) else {
                return
            }
            place()
            content.add(rig.rootEntity)
        }
        .personaHold(
            target: rig.tapTarget,
            onTap: {
                guard viewModel.connectionStatus == .connected else { return }
                viewModel.toggleListening()
            },
            onHold: onLeave,
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
        .onChange(of: viewModel.personaVisualization) { _, visualization in
            rig.apply(visualization: visualization)
            if let geometry = visualization.faceGeometry {
                rig.apply(faceGeometry: geometry)
            }
            // Her size changed, so where she stands did too.
            place()
        }
    }

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

    /// Real post-process bloom, and the one place it exists.
    ///
    /// visionOS blooms only in an immersive space -- no effect in a volume or
    /// the shared space -- which is why the volume falls back to an emissive
    /// billboard halo and why `realBloomActive` is a mode rather than a
    /// preference. Numbers device-tuned in Valinor.
    ///
    /// `.unbounded` rather than `.hierarchical` deliberately: a hierarchical
    /// scope blooms a bounded region and leaves a hard disc edge where that
    /// region ends, which Apple warns about. Unbounded blooms the whole frame
    /// and the threshold is what keeps the passthrough room out of it -- only
    /// something as bright as the bead clears 0.5.
    ///
    /// NOT applied to a model persona. Bloom is a fact about a bead, which is a
    /// light; Selene has no emissive shell to clear any threshold, and a person
    /// standing in your room haloed in fire is a different proposition. See
    /// `PersonaRig.isCorporeal`.
    private func applyBloom() {
        guard !rig.isCorporeal else {
            rig.rootEntity.components.remove(BloomComponent.self)
            rig.rootEntity.components.remove(BloomSettingsComponent.self)
            return
        }
        var bloom = BloomComponent()
        bloom.scope = .unbounded
        rig.rootEntity.components.set(bloom)

        var settings = BloomSettingsComponent()
        settings.strength = 0.9
        settings.threshold = 0.5
        rig.rootEntity.components.set(settings)
    }
}
