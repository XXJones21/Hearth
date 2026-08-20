//
//  FlameProfile.swift
//  HearthUI
//
//  The flame's SHAPE as pure arithmetic, with no renderer in it.
//
//  Every function here is lifted unchanged from `FlameMesh`, which builds the
//  headset's flame as a `LowLevelMesh`. It is duplicated rather than shared for
//  one reason: `FlameMesh` is `@MainActor` and RealityKit-typed, and HearthUI
//  must not depend on RealityKit -- the dependency runs the other way. What is
//  copied is a page of trigonometry with no platform in it.
//
//  WHY THAT DUPLICATION IS TOLERABLE, and it is the whole reason a 2D flame is
//  cheap: the silhouette is not an approximation of the headset's. It is the
//  SAME curve. A surface of revolution seen from the front has its outline at
//  the two meridians where x is extremal -- angle 0 and angle pi -- so a 2D
//  client evaluates exactly what a 3D client evaluates, at two angles instead
//  of forty-four.
//
//  See wiki/raw/persona-flame-spec.md for the full walkthrough and for what a
//  2D drawing gives up (fine grain, depth, any path to rotating it).
//

import Foundation
import CoreGraphics

/// The flame's silhouette and colour, evaluated on the CPU.
public struct FlameProfile: Sendable {
    /// Half-width at the flame's widest, and total height, in whatever units
    /// the caller is drawing in.
    public var radius: Double
    public var height: Double

    /// How much the silhouette wanders. Zero is a smooth teardrop -- useful for
    /// seeing the profile on its own, useless as fire.
    public var turbulence: Double = 0.28
    /// How far the tip leans as it rises, which is what stops a flame reading
    /// as a symmetrical vase.
    public var sway: Double = 0.16

    public init(radius: Double, height: Double) {
        self.radius = radius
        self.height = height
    }

    /// Where the rounded base gives way to the taper, and how deep that base
    /// hangs below the origin.
    static let domeTop = 0.3
    static let domeDepth = 0.95

    /// How wide the flame is at a given height parameter.
    ///
    /// Two pieces, because the base and the body want different curves: a
    /// hemisphere below `domeTop`, then a rounded shoulder and a long taper.
    /// Squaring `t` inside the taper is what keeps the flame near full width
    /// through its lower third -- without it the silhouette is a cone.
    public func width(at v: Double, phase: Double) -> Double {
        // Almost invisible on purpose. A flame does not pulse as a whole; its
        // EDGES move, and that is the turbulence's job.
        let breath = 1 + 0.012 * sin(phase * 1.6)
        if v < Self.domeTop {
            let t = v / Self.domeTop
            return radius * sin(t * .pi / 2) * breath
        }
        let t = (v - Self.domeTop) / (1 - Self.domeTop)
        return radius * pow(max(1 - t * t, 0), 0.45) * breath
    }

    /// How high up the flame a given `v` sits. Not linear: across the dome the
    /// height follows the same quarter circle the width does, so the two
    /// together describe a hemisphere rather than a spike.
    public func rise(at v: Double) -> Double {
        let base = -radius * Self.domeDepth
        if v < Self.domeTop {
            let t = v / Self.domeTop
            return base + radius * Self.domeDepth * (1 - cos(t * .pi / 2))
        }
        let t = (v - Self.domeTop) / (1 - Self.domeTop)
        return base + radius * Self.domeDepth + (height - radius * Self.domeDepth) * t
    }

    /// How far the flame leans sideways at a given height. Nothing at the base
    /// -- it is attached to something -- growing with the square of the height,
    /// so the lean is all in the top third.
    public func lean(at v: Double, phase: Double) -> Double {
        sway * radius * v * v * sin(phase * 1.7)
    }

    /// Cheap, seamless, deterministic wobble.
    ///
    /// Trigonometric rather than a noise table: sines of INTEGER multiples of
    /// the angle agree at 0 and 2pi for free, which a body that closes on
    /// itself needs. Damped to nothing at the base, because a flame is held
    /// steady by whatever it is burning on.
    public static func noise(angle: Double, height v: Double, phase: Double) -> Double {
        let a = sin(3 * angle + phase * 2.1 + v * 5.0)
        let b = sin(5 * angle - phase * 1.6 + v * 8.0) * 0.55
        let c = sin(8 * angle + phase * 2.9 - v * 3.0) * 0.3
        return (a + b + c) / 1.85 * smoothstep(domeTop, 1.0, v)
    }

    /// The surface's distance from the axis, on one meridian, right now.
    public func surface(at v: Double, angle: Double, phase: Double) -> Double {
        let wobble = 1 + turbulence * Self.noise(angle: angle, height: v, phase: phase)
        return width(at: v, phase: phase) * max(wobble, 0.05)
    }

    /// The VISIBLE top, not the geometric one. The mesh runs to a point and the
    /// density has faded it to nothing well before that, so the tip is drawn
    /// and never seen.
    public var visibleTop: Double { rise(at: 0.95) }

    /// Where the density feather takes the flame to nothing.
    public static let fadeStart = 0.88
    public static let fadeEnd = 0.99

    /// How opaque the flame is at a given height -- the tip feather only. The
    /// interior noise that tatters a real flame's upper half is what a 2D
    /// drawing gives up.
    public static func opacity(at v: Double) -> Double {
        1 - smoothstep(fadeStart, fadeEnd, v)
    }

    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
