//
//  PersonaFlameView.swift
//  Hearth
//
//  Route B of the iOS renderer investigation: the headset's persona rig, in a
//  flat RealityView, with every room effect switched off.
//
//  THE QUESTION THIS EXISTS TO ANSWER. Sulivan is a fire on the headset and an
//  orb on the phone, which is two characters wearing one name. There are two
//  ways to close that:
//
//    A. Draw the flame in SwiftUI, the way `PersonaOrb` already draws the bead
//       -- gradients and filled paths, no shader, no 3D. See the recipe in
//       wiki/raw/persona-flame-spec.md.
//    B. Host the SAME rig the headset runs, in a RealityView, with the lights
//       off and the particles kept. This file.
//
//  B is here first because it is nearly free, and that is not an accident. The
//  package builds for iOS deliberately, `PersonaRig.init(embedCamera:)` was
//  written for "a flat iOS RealityView needs the scene to carry its own
//  camera", and `EffectBudget.flat` already states what a phone is allowed to
//  do. Every seam this needs was cut before there was anything to put through
//  it. So the honest first move is to look at B on a device before spending a
//  week building A -- and A still has to exist afterwards regardless, because
//  widgets can host neither a RealityView nor a compute pass.
//
//  WHAT `.flat` TURNS OFF, and why none of it is a loss here: the surroundings
//  light and the proximity spotlight both need physical surfaces, and a phone
//  has none. What survives is the flame, its face and its embers, which is the
//  whole character.
//

import SwiftUI
import RealityKit
import HearthCore
import HearthSpatial

struct PersonaFlameView: View {
    let state: HearthState
    /// TTS amplitude while speaking, mic level while listening. The rig makes
    /// the same use of it either way -- see `PersonaRig.audioLevel`.
    var level: Float = 0
    var palette: PersonaPalette = .fallback
    var visualization: PersonaVisualization = .fallback

    /// EMBEDS A CAMERA, which the headset's rig must never do. A volumetric
    /// window or an immersive space has the system's own viewer pose and
    /// creating a PerspectiveCamera inside one crashes the device; a flat
    /// RealityView has no viewer at all until you give it one.
    @StateObject private var rig = PersonaRig(embedCamera: true)

    var body: some View {
        RealityView { content in
            content.add(rig.rootEntity)
            // A phone shows the persona at a fixed size in a panel, so unlike
            // the headset there is no gesture that resizes it and no anchor
            // that remembers one. The camera distance in `embedCamera` frames
            // the bead; the flame is taller than the bead, so the rig is pulled
            // back a little rather than the camera being moved -- the camera's
            // framing is the rig's own business and this view should not reach
            // into it.
            rig.rootEntity.position = SIMD3<Float>(0, -0.10, 0)

            // The phone's budget: no light on surroundings, no proximity spot,
            // a thinner ember field. Stated before the style, because the style
            // builds effects that read it.
            rig.configure(for: .flat)
            rig.effectStyle = .fire

            rig.apply(palette)
            rig.apply(visualization: visualization)
            if let geometry = visualization.faceGeometry {
                rig.apply(faceGeometry: geometry)
            }
            rig.updateState(PersonaState(state))
            rig.setConnected(true)
        }
        // Edges only, exactly as the volume does it. The rig early-returns on
        // an unchanged value, but a per-frame write to a @Published is a
        // notification whether or not anything changed.
        .onChange(of: state) { _, new in rig.updateState(PersonaState(new)) }
        .onChange(of: level) { _, new in rig.audioLevel = new }
        .onChange(of: palette) { _, new in rig.apply(new) }
        .onChange(of: visualization) { _, new in
            rig.apply(visualization: new)
            if let geometry = new.faceGeometry { rig.apply(faceGeometry: geometry) }
        }
    }
}
