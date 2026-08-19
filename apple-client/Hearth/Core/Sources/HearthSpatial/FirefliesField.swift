//
//  FirefliesField.swift
//  HearthSpatial
//
//  The default preset: 96 emissive dots on a deterministic shell, choreographed
//  into four shapes.
//
//  This file is a MOVE, not a rewrite. Every number and every comment below was
//  judged on a headset over the course of phases 1 through 4, and the reason it
//  now lives behind `ParticleChoreography` is that a second preset arrived --
//  not that anything here was found wanting. Where the fire's embers are born
//  and forgotten, these dots are named: each one's position is stated every
//  frame, which is the only way to draw a ring, a waveform or a portal. A
//  simulator cannot be told to spell something out.
//
//  THE ONE THING THAT CHANGED IN THE MOVE. `spinAngle` used to be rig state
//  shared with the bead's own rotation; it is field state now, because a field
//  that borrows the rig's spin is a field that cannot be swapped out without
//  leaving a number behind.
//

import Foundation
import RealityKit
import simd
import HearthCore

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class FirefliesField: ParticleChoreography {
    public static let preset: ParticlePreset = .fireflies

    public let root = Entity()

    // MARK: - The field

    private var entities: [ModelEntity] = []
    private var basePositions: [SIMD3<Float>] = []
    private var orbitAngles: [Float] = []
    private var orbitSpeeds: [Float] = []
    private var animSpeeds: [Float] = []
    private var verticalSpeeds: [Float] = []
    /// Per-particle twinkle offsets, so the idle field breathes out of step
    /// with itself rather than pulsing as one lamp.
    private var twinklePhases: [Float] = []
    private var twinkleSpeeds: [Float] = []
    /// True while the field is carrying per-particle opacity. Lets the other
    /// states clear it exactly once instead of writing 96 components a frame to
    /// say "still fully visible".
    private var twinkling = false

    private var world: ParticleWorld
    private var palette: PersonaPalette

    private var spinAngle: Float = 0

    // MARK: - The visualization spec (sulivan.json)

    private let count = 96
    private let dotRadius: Float = 0.010
    private let metallic: Float = 0.5
    private let roughness: Float = 0.4

    public init(world: ParticleWorld, palette: PersonaPalette) {
        self.world = world
        self.palette = palette
        root.name = "FirefliesField"
        build()
    }

    // MARK: - Construction

    private func build() {
        // Deterministic Fibonacci shell: the same field every launch, and the
        // same field every client.
        let golden = Float.pi * (3.0 - sqrt(5.0))
        let mesh = MeshResource.generateSphere(radius: dotRadius)
        let material = dotMaterial()

        for i in 0..<count {
            let y = 1.0 - (Float(i) / Float(count - 1)) * 2.0
            let r = sqrt(max(0, 1.0 - y * y))
            let theta = golden * Float(i)
            let innerEdge = world.coreRadius + 0.04
            let dist = innerEdge + particleNoise(i) * (world.maxDistance - innerEdge)
            let pos = SIMD3<Float>(cos(theta) * r * dist, y * dist, sin(theta) * r * dist)
            basePositions.append(pos)

            orbitAngles.append(theta)
            orbitSpeeds.append(0.10 + particleNoise(i + 101) * 0.30)
            animSpeeds.append(0.10 + particleNoise(i + 211) * 0.50)
            verticalSpeeds.append((particleNoise(i + 307) - 0.5) * 0.40)
            twinklePhases.append(particleNoise(i + 401) * .pi * 2)
            twinkleSpeeds.append(0.55 + particleNoise(i + 509) * 0.75)

            let dot = ModelEntity(mesh: mesh, materials: [material])
            dot.position = pos
            root.addChild(dot)
            entities.append(dot)
        }
    }

    /// Factored out so a palette swap can re-tint all 96 dots at once.
    private func dotMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color(palette.particle))
        material.metallic = .init(floatLiteral: metallic)
        material.roughness = .init(floatLiteral: roughness)
        material.clearcoat = .init(floatLiteral: 1.0)
        material.clearcoatRoughness = .init(floatLiteral: 0.1)
        material.emissiveColor = .init(color: color(palette.particle))
        // The metallic body darkens the dot, so the emissive has to clear the
        // bloom threshold (the orb blooms around 1.7 to 2.9). 1.15 was under it
        // and the field simply did not glow.
        material.emissiveIntensity = 2.5
        return material
    }

    // MARK: - ParticleChoreography

    public func apply(palette newPalette: PersonaPalette) {
        guard newPalette != palette else { return }
        palette = newPalette
        let material = dotMaterial()
        for dot in entities { dot.model?.materials = [material] }
    }

    /// The shell is baked into `basePositions`, so a reshape would mean
    /// rebuilding 96 entities. It is recorded and otherwise ignored: the
    /// fireflies orbit a bead whose radius is a constant of the design, and the
    /// preset that changes shape underneath its field is the fire, not this one.
    public func reshape(to newWorld: ParticleWorld) {
        world = newWorld
    }

    public func update(_ frame: ParticleFrame) {
        // The switch flourish overrides the per-state choreography while the
        // hold builds.
        if frame.transition > 0.01 {
            updateSwitch(frame, progress: min(1, frame.transition))
            return
        }
        switch frame.state {
        case .listening: updateListening(frame)
        case .thinking:  updateThinking(frame)
        case .speaking:  updateSpeaking(frame)
        case .resting:   updateShell(frame, pulse: 0)
        }
    }

    // MARK: - Per-state choreography

    /// Resting: dots ride their base shell, the field spins and expands, and
    /// each dot fades in and out on its own clock.
    ///
    /// The twinkle is what turns a swarm into fireflies. At rest the field's job
    /// is to say the house is alive, and 96 dots all present at once say it by
    /// crowding the face -- the one thing on the orb worth looking at. Fading
    /// each in and out means the field is never fully in front of the face and
    /// never fully absent either.
    private func updateShell(_ frame: ParticleFrame, pulse: Float) {
        spinAngle += frame.spin * frame.dt * Float.pi * 2
        root.orientation = simd_quatf(angle: spinAngle, axis: SIMD3<Float>(0, 1, 0))
        root.scale = SIMD3<Float>(repeating: 1.0 + 0.5 * frame.motion + 0.3 * pulse)
        for i in entities.indices {
            entities[i].position = basePositions[i]
            // A raised sine, floored at ZERO. Each dot is genuinely absent for
            // half its cycle rather than merely dim.
            //
            // The floor was 0.12 and that was the whole failure: a hundred dots
            // at a tenth opacity are still a hundred dots, so the field read as
            // cluttered haze instead of fireflies. Vanishing outright is what
            // declutters WITHOUT losing particles -- the same field, a third of
            // it visible at any moment.
            //
            // OpacityComponent rather than per-particle materials: 96 material
            // assignments a frame to change one number would be absurd, and
            // this is the component that exists for exactly this.
            let wave = sin(frame.time * twinkleSpeeds[i] + twinklePhases[i])
            entities[i].components.set(OpacityComponent(opacity: max(0, wave)))
        }
        twinkling = true
    }

    /// Put every dot back to full opacity, once.
    ///
    /// Called by the states that do not twinkle. Guarded because it only needs
    /// to happen on the way out of idle, and writing 96 components a frame to
    /// say "still fully visible" is work for nothing.
    private func clearTwinkle() {
        guard twinkling else { return }
        twinkling = false
        for dot in entities {
            dot.components.set(OpacityComponent(opacity: 1))
        }
    }

    /// Listening: a firefly swirl in the VERTICAL plane, widening with the mic.
    ///
    /// Turned a quarter from Valinor's, and the reason is the face. The
    /// original swirls around the Y axis, which on a bead with no face is a
    /// pleasing halo and on a bead WITH one is a curtain drawn across it. Swung
    /// into the plane the viewer faces, the same motion frames the face instead
    /// of crossing it. The z jitter is what keeps it from reading as a flat
    /// sticker: the dots still have depth, they just no longer orbit through
    /// the eyes.
    private func updateListening(_ frame: ParticleFrame) {
        root.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        root.scale = .one
        clearTwinkle()
        let maxD = world.maxDistance
        for i in entities.indices {
            orbitAngles[i] += orbitSpeeds[i] * frame.dt * 4
            let angle = orbitAngles[i]
            let pulsing = 0.5 + 0.5 * sin(frame.time * animSpeeds[i])
            let dist = maxD * min(1, 0.6 + 0.4 * pulsing)
            let breathe = sin(frame.time * 0.5 + angle) * 0.05 * maxD
            let jitterZ = sin(frame.time * verticalSpeeds[i]) * 0.18 * maxD
            entities[i].position = SIMD3<Float>(
                cos(angle) * (dist + breathe),
                sin(angle) * (dist + breathe),
                jitterZ)
        }
    }

    /// Thinking: the ring stood upright, roughly twice as fast.
    ///
    /// Valinor's is a flat Saturn ring at the bead's height, which from the
    /// front is a line straight through the eyes. Stood up into the viewer's
    /// plane it becomes a halo around the face -- the same shape, doing the
    /// opposite thing to the one feature that matters.
    private func updateThinking(_ frame: ParticleFrame) {
        root.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        root.scale = .one
        clearTwinkle()
        let ringD = world.maxDistance * 0.86
        for i in entities.indices {
            orbitAngles[i] += orbitSpeeds[i] * frame.dt * 8
            let angle = orbitAngles[i]
            entities[i].position = SIMD3<Float>(cos(angle) * ringD, sin(angle) * ringD, 0)
        }
    }

    /// The switch flourish: a TILTED portal ring, deliberately distinct from
    /// the flat thinking ring so the two never read as the same event.
    private func updateSwitch(_ frame: ParticleFrame, progress: Float) {
        root.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        root.scale = .one
        clearTwinkle()
        let n = entities.count
        let ringD = world.maxDistance * (1.0 - 0.3 * progress)
        let tilt: Float = 0.6
        let spin = frame.time * (3.0 + 6.0 * progress)
        for i in entities.indices {
            let t = n <= 1 ? 0 : Float(i) / Float(n)
            let angle = t * Float.pi * 2 + spin
            let x = cos(angle) * ringD
            let yFlat = sin(angle) * ringD
            let y = yFlat * cos(tilt)
            let z = yFlat * sin(tilt)
            entities[i].position = mix(basePositions[i], SIMD3<Float>(x, y, z), progress)
        }
    }

    /// Speaking: a horizontal waveform line whose height is the real playback
    /// amplitude, in front of the bead and facing the viewer.
    private func updateSpeaking(_ frame: ParticleFrame) {
        root.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        root.scale = .one
        clearTwinkle()
        let n = entities.count
        let width = world.maxDistance * 1.8
        let halfW = width / 2
        // A small floor keeps the line alive between syllables.
        let amp = (0.04 + 0.5 * frame.level) * world.maxDistance
        let z = world.coreRadius + 0.06
        for i in entities.indices {
            let t = n <= 1 ? 0 : Float(i) / Float(n - 1)
            let x = -halfW + t * width
            // Two components, so it wiggles like a voice rather than a sine.
            let phase = x * 14.0 + frame.time * 7.0
            let y = amp * (sin(phase) * 0.7 + sin(phase * 0.5 + frame.time * 3.0) * 0.3)
            entities[i].position = SIMD3<Float>(x, y, z)
        }
    }

    // MARK: - Helpers

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    private func color(_ c: SIMD3<Float>, alpha: Float = 1) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(alpha))
    }
}
