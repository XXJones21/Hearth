//
//  FlameMesh.swift
//  HearthSpatial
//
//  The flame's SHAPE, as geometry that moves.
//
//  WHY GEOMETRY AND NOT A TEXTURE. The first flame was an animated opacity map
//  on a sphere, and it worked -- it read as fire, it lit a real wall, and it
//  proved the whole mechanism. What it could not do was stop being a sphere. A
//  texture carves INWARD: it can put holes in a ball, and it can never put a
//  tongue of flame outside one. Every frame of that test had a hard circular
//  edge along the bottom, because that is where the geometry ended, and no
//  amount of tuning a texture fixes a silhouette.
//
//  So the silhouette becomes the mesh's job and the texture keeps the internal
//  structure. They answer different questions and both are wanted.
//
//  A TEARDROP PINCHED AT BOTH ENDS. A candle flame is not a sphere with an
//  interesting top: it narrows at the base where it meets its source, swells
//  through the middle, and draws to a wandering point. The profile function
//  here is that whole silhouette rather than an edit applied to a ball, which
//  is what lets the base taper as honestly as the tip does.
//
//  WRITTEN ON THE CPU, deliberately, and this is the one thing here that might
//  change. A ring-and-segment sphere at this tessellation is about twelve
//  hundred vertices -- a rounding error against everything else the room is
//  doing -- and `LowLevelMesh` also offers GPU buffers if that stops being
//  true. Starting on the CPU keeps the profile readable as arithmetic instead
//  of scattering it across a second Metal pipeline, and the shape is the part
//  still being designed.
//

import Foundation
import os
import RealityKit
import simd

@MainActor
public final class FlameMesh {
    private static let log = Logger(subsystem: "com.hearth.spatial", category: "flame")

    /// One vertex, laid out to match the descriptor below exactly. A mismatch
    /// between this and `vertexAttributes` is silent and draws confetti.
    private struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var uv: SIMD2<Float>
    }

    /// Hand this to a `ModelComponent`.
    public private(set) var resource: MeshResource

    private let mesh: LowLevelMesh
    private let rings: Int
    private let segments: Int

    /// How tall and how wide the flame is, in the entity's own units.
    ///
    /// Expressed as multiples of the bead's radius by the caller, so a flame
    /// stays the same shape whatever size the persona has been pinched to.
    public var radius: Float
    public var height: Float

    /// How much the silhouette wanders. Zero is a smooth teardrop -- useful for
    /// seeing the profile on its own, useless as fire.
    public var turbulence: Float = 0.28

    /// How far the tip leans as it rises, which is what stops a flame reading
    /// as a symmetrical vase.
    public var sway: Float = 0.16

    public init?(radius: Float, height: Float, rings: Int = 28, segments: Int = 44) {
        self.radius = radius
        self.height = height
        self.rings = rings
        self.segments = segments

        // A closed ring costs one duplicated column of vertices, and that is the
        // right trade: sharing the seam column would force u to be both 0 and 1
        // at the same vertex, and the texture would mirror down one side.
        let vertexCount = (rings + 1) * (segments + 1)
        let indexCount = rings * segments * 6

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = vertexCount
        descriptor.indexCapacity = indexCount
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
            .init(semantic: .normal, format: .float3, layoutIndex: 0,
                  offset: MemoryLayout<SIMD3<Float>>.stride),
            .init(semantic: .uv0, format: .float2, layoutIndex: 0,
                  offset: MemoryLayout<SIMD3<Float>>.stride * 2),
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferOffset: 0, bufferStride: MemoryLayout<Vertex>.stride)
        ]
        descriptor.indexType = .uint32

        guard let mesh = try? LowLevelMesh(descriptor: descriptor) else {
            Self.log.error("LowLevelMesh(descriptor:) threw -- no flame geometry")
            return nil
        }
        guard let resource = try? MeshResource(from: mesh) else {
            Self.log.error("MeshResource(from:) threw -- no flame geometry")
            return nil
        }
        self.mesh = mesh
        self.resource = resource

        writeIndices()
        update(phase: 0)
        Self.log.notice("ready -- \(rings)x\(segments), \(vertexCount) vertices")
    }

    /// The triangles, written ONCE.
    ///
    /// The topology never changes -- only where the vertices are -- so this is
    /// the half of the mesh that does not belong in the per-frame path.
    private func writeIndices() {
        mesh.replaceUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt32.self)
            var i = 0
            for ring in 0..<rings {
                for segment in 0..<segments {
                    let a = UInt32(ring * (segments + 1) + segment)
                    let b = a + 1
                    let c = a + UInt32(segments + 1)
                    let d = c + 1
                    indices[i + 0] = a; indices[i + 1] = c; indices[i + 2] = b
                    indices[i + 3] = b; indices[i + 4] = c; indices[i + 5] = d
                    i += 6
                }
            }
        }
    }

    /// Re-shape the flame for a moment in time.
    ///
    /// `phase` is seconds on the lantern's own clock, and it is deliberately
    /// passed in rather than kept here: the mesh, the texture, the light colour
    /// and the embers all have to agree about when "now" is, or the room ends
    /// up with four effects near each other instead of one fire.
    public func update(phase: Float) {
        var lowest = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var highest = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for ring in 0...rings {
                let v = Float(ring) / Float(rings)          // 0 at the base, 1 at the tip
                let profile = self.profile(at: v, phase: phase)
                let lean = self.lean(at: v, phase: phase)
                let y = self.rise(at: v)

                for segment in 0...segments {
                    let u = Float(segment) / Float(segments)
                    let angle = u * 2 * .pi

                    // The wobble is per-MERIDIAN as well as per-height, so the
                    // flame is not a surface of revolution -- a body that is
                    // round from every angle reads as a vase, not a fire.
                    // Damped to nothing at the base, where the dome has to stay
                    // a dome.
                    let wobble = 1 + turbulence * Self.noise(angle: angle, height: v, phase: phase)
                    let r = profile * max(wobble, 0.05)

                    let position = SIMD3<Float>(cos(angle) * r + lean.x,
                                                y,
                                                sin(angle) * r + lean.y)
                    // Radial normals. Correct enough for something emissive,
                    // and honest about it: this surface is not being shaded by
                    // the room, it IS the light.
                    let normal = simd_length(SIMD2(position.x, position.z)) > 0.0001
                        ? simd_normalize(SIMD3<Float>(position.x, 0.35, position.z))
                        : SIMD3<Float>(0, 1, 0)

                    vertices[ring * (segments + 1) + segment] =
                        Vertex(position: position, normal: normal, uv: SIMD2<Float>(u, v))

                    lowest = simd_min(lowest, position)
                    highest = simd_max(highest, position)
                }
            }
        }

        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexOffset: 0,
                              indexCount: rings * segments * 6,
                              topology: .triangle,
                              materialIndex: 0,
                              bounds: BoundingBox(min: lowest, max: highest))
        ])
    }

    /// How wide the flame is at a given height.
    ///
    /// REWRITTEN AFTER THE FIRST DEVICE RUN, which produced a light bulb:
    /// widest near the top, drawn to a point at the bottom. Exactly upside
    /// down. A candle flame is fattest LOW -- just above whatever it is burning
    /// on -- and spends the rest of its height tapering.
    ///
    /// Two pieces, because the base and the body want different curves:
    ///
    /// - Below `domeTop` it is a HEMISPHERE, swelling from the base to full
    ///   width. That is what stops the bottom being a spike. A profile that
    ///   simply goes to zero at v = 0 gives a cone point, and the first run had
    ///   one; a dome needs the height to curve with the width, which is why
    ///   `rise(at:)` exists alongside this.
    /// - Above it, a long taper to nothing, with the power set so the flame
    ///   thins slowly at first and quickly near the tip.
    private func profile(at v: Float, phase: Float) -> Float {
        let breath = 1 + 0.06 * sin(phase * 2.3)

        if v < Self.domeTop {
            // A quarter circle: full width at the dome's top, zero at its pole,
            // and the vertical half of the same circle is in `rise`.
            let t = v / Self.domeTop
            return radius * sin(t * .pi / 2) * breath
        }

        // A ROUNDED SHOULDER, then a taper. `pow(1 - t, n)` was the first cut
        // and it is very nearly a straight line near the base, which is why the
        // device showed a CONE: full width at the bottom and a ruler-straight
        // edge all the way to the point. Squaring `t` inside keeps the flame
        // near full width through its lower third and moves all of the
        // narrowing into the top half, which is where a flame's narrowing is.
        let t = (v - Self.domeTop) / (1 - Self.domeTop)
        // The exponent is the top's width: LOWER is wider, because it flattens
        // the curve's shoulder and pushes the narrowing later. 0.62 gave a top
        // that drew in too early and read as pinched.
        return radius * pow(max(1 - t * t, 0), 0.45) * breath
    }

    /// How high up the flame a given `v` sits.
    ///
    /// Not linear, and that is what makes the base a dome rather than a cone:
    /// across the bottom section the height follows the same quarter circle the
    /// width does, so the two together describe a hemisphere. Above it, height
    /// runs straight.
    private func rise(at v: Float) -> Float {
        let base = -radius * Self.domeDepth
        if v < Self.domeTop {
            let t = v / Self.domeTop
            return base + radius * Self.domeDepth * (1 - cos(t * .pi / 2))
        }
        let t = (v - Self.domeTop) / (1 - Self.domeTop)
        return base + radius * Self.domeDepth + (height - radius * Self.domeDepth) * t
    }

    /// Where the rounded base gives way to the taper, and how deep that base
    /// hangs below the flame's origin.
    ///
    /// A fifth of the rings spent on the dome is enough to read as round and
    /// cheap enough not to care about.
    ///
    /// Both raised after the second device run. At a fifth of the rings and
    /// just over half a radius deep, the dome was too shallow to read as round
    /// at all -- what showed was a hard rim where the widest ring sat, with
    /// almost nothing below it.
    private static let domeTop: Float = 0.3
    private static let domeDepth: Float = 0.95

    /// How far the flame leans at a given height.
    ///
    /// Nothing at the base -- it is attached to something -- growing with the
    /// square of the height so the lean is all in the top third, which is where
    /// a real flame's is.
    private func lean(at v: Float, phase: Float) -> SIMD2<Float> {
        let reach = sway * radius * v * v
        return SIMD2<Float>(reach * sin(phase * 1.7),
                            reach * sin(phase * 1.3 + 2.1))
    }

    /// Cheap, seamless, deterministic wobble.
    ///
    /// Trigonometric rather than a noise table, and the reason is the seam: the
    /// flame closes on itself in u, so anything sampled here has to agree at
    /// angle 0 and angle 2*pi. Sines of INTEGER multiples of the angle do that
    /// for free. A hash-based noise would need the same circle trick the fire
    /// kernel uses, for a wobble that is three octaves at most.
    private static func noise(angle: Float, height: Float, phase: Float) -> Float {
        let a = sin(3 * angle + phase * 2.1 + height * 5.0)
        let b = sin(5 * angle - phase * 1.6 + height * 8.0) * 0.55
        let c = sin(8 * angle + phase * 2.9 - height * 3.0) * 0.3
        // Weighted toward the top: a flame's base is held steady by whatever it
        // is burning on, and only the tip is free to wander.
        // Damped to nothing at the base and free at the tip. A flame is held
        // steady by whatever it is burning on, and the first run's wobble ran
        // all the way down -- which chewed the dome into a knot of folds.
        let freedom = smoothstep(domeTop, 1.0, height)
        return (a + b + c) / 1.85 * freedom
    }

    /// The usual smooth ramp, which Foundation does not have.
    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
