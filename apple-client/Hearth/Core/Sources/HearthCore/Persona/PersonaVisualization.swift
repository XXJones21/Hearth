//
//  PersonaVisualization.swift
//  Hearth
//
//  How a persona wants to be DRAWN, straight from its own config. Valar's
//  `public_config()` forwards the whole `visualization` block verbatim, so this
//  needs no server change -- the same route `state_colors` took.
//
//  The renderer is chosen by `type`, never by name. Nothing in the client says
//  "if Selene": a persona declares `sphere_particle` or `glb_animated` and the
//  stage honours it, which is what lets Sage arrive with no client change.
//

import Foundation

/// The one numeric coercion for persona JSON in this module.
///
/// Persona configs are decoded with `JSONSerialization` and optional casts, not
/// `Codable`, because a house one field ahead of a client must still render.
/// That tolerance is only real if every reader coerces the same way: `1` is an
/// Int, `1.0` a Double, and both arrive as NSNumber often enough that a strict
/// cast silently drops a value and falls back to a default nobody chose.
/// `PersonaPalette` calls this too -- there is deliberately not a second one.
func personaNum(_ any: Any?) -> Double? {
    if let n = any as? NSNumber { return n.doubleValue }
    if let d = any as? Double { return d }
    if let i = any as? Int { return Double(i) }
    return nil
}

/// Appearance only, normalised to the head's own bounding box. Motion never
/// lives here -- the director owns every channel that moves, which is what
/// lets a persona's dozen numbers drive the whole expression library instead
/// of authoring an animation set. Defaults are the warm_round archetype, so a
/// partial block still renders a face rather than a pile of zeroes.
/// Spec: wiki/raw/persona-face-spec.md.
public struct FaceGeometry: Sendable, Equatable {
    public var headWidth = 1.0, headHeight = 1.05, headRoundness = 0.8
    public var eyeSize = 0.1, eyeSpacing = 0.38, eyeHeight = 0.45
    public var eyeLength = 2.4, eyeTilt = 0.0
    public var mouthWidth = 0.34, mouthThickness = 0.05, mouthCurve = 0.26

    public init() {}
}

public struct PersonaVisualization: Equatable {
    public enum Kind: String {
        /// Procedural orb (Sulivan). Rendered by PersonaCanvasView.
        case sphereParticle = "sphere_particle"
        /// Character model (Selene, soon Sage). Rendered by RealityKit.
        case glbAnimated = "glb_animated"
        /// The eyes-first procedural face. Rendered by PersonaFaceView.
        case proceduralFace = "procedural_face"
    }

    public var kind: Kind = .sphereParticle
    /// Present only for a `procedural_face` config that carried a geometry
    /// block. Nil is the honest state for a face whose numbers never arrived.
    public var faceGeometry: FaceGeometry?
    /// State name -> Valar-relative USDZ path, e.g.
    /// "idle" -> "Selene/Assets/usdz/selene-idle.usdz".
    public var usdzClips: [String: String] = [:]
    /// Degrees, from the config, so a model authored facing away can be turned.
    public var rotationY: Double = 0

    public static let fallback = PersonaVisualization()

    /// A glb persona with no USDZ clips cannot be drawn by RealityKit, so the
    /// stage falls back to its 2D orb rather than showing an empty volume.
    public var canRenderModel: Bool {
        kind == .glbAnimated && usdzClips["idle"] != nil
    }

    /// A face config that arrived without its geometry falls back to the orb,
    /// the same contract `canRenderModel` uses for a clipless model. The two
    /// halves of "a face" -- the type and the numbers -- travel together or
    /// the stage draws what it already knows how to draw.
    public var canRenderFace: Bool {
        kind == .proceduralFace && faceGeometry != nil
    }

    public static func from(visualization: [String: Any]?, personaName: String) -> PersonaVisualization {
        guard let visualization else { return .fallback }
        var out = PersonaVisualization()

        if let raw = visualization["type"] as? String {
            if let kind = Kind(rawValue: raw) {
                out.kind = kind
            } else {
                // Silence here costs an hour: an unknown type renders the orb,
                // which is indistinguishable from a persona that asked for the
                // orb. Say which type went unrecognised.
                print("PersonaVisualization: unknown type '\(raw)' for \(personaName); rendering the orb")
            }
        }
        if out.kind == .proceduralFace, let geo = visualization["geometry"] as? [String: Any] {
            var g = FaceGeometry()
            func f(_ key: String, _ fallback: Double) -> Double { personaNum(geo[key]) ?? fallback }
            g.headWidth = f("head_width", g.headWidth)
            g.headHeight = f("head_height", g.headHeight)
            g.headRoundness = f("head_roundness", g.headRoundness)
            g.eyeSize = f("eye_size", g.eyeSize)
            g.eyeSpacing = f("eye_spacing", g.eyeSpacing)
            g.eyeHeight = f("eye_height", g.eyeHeight)
            g.eyeLength = f("eye_length", g.eyeLength)
            g.eyeTilt = f("eye_tilt", g.eyeTilt)
            g.mouthWidth = f("mouth_width", g.mouthWidth)
            g.mouthThickness = f("mouth_thickness", g.mouthThickness)
            g.mouthCurve = f("mouth_curve", g.mouthCurve)
            out.faceGeometry = g
        }
        if let usdz = visualization["usdz"] as? [String: Any] {
            out.usdzClips = usdz.compactMapValues { $0 as? String }
        }
        if let rotation = visualization["rotation"] as? [String: Any] {
            out.rotationY = (rotation["y"] as? Double) ?? Double(rotation["y"] as? Int ?? 0)
        }

        // A glb persona whose server config has no usdz map yet: fall back to
        // anything bundled under the same name. That is what lets the model be
        // tested before Valar's checkout has the files, and it keeps a shipped
        // persona renderable against an older server.
        if out.kind == .glbAnimated && out.usdzClips.isEmpty {
            out.usdzClips = Self.bundledClips(for: personaName)
        }
        return out
    }

    /// Bare filenames (no slash) mean "in the app bundle"; anything else is a
    /// Valar-relative path.
    private static func bundledClips(for personaName: String) -> [String: String] {
        let base = personaName.lowercased()
        var found: [String: String] = [:]
        for state in ["idle", "listening", "thinking", "speaking"] {
            if Bundle.main.url(forResource: "\(base)-\(state)", withExtension: "usdz") != nil {
                found[state] = "\(base)-\(state).usdz"
            }
        }
        return found
    }

    /// Absolute URL for a state's clip: the bundle when the entry is a bare
    /// filename, otherwise the Valar origin like every other persona asset.
    public func clipURL(for state: String) -> URL? {
        guard let path = usdzClips[state] else { return nil }
        if !path.contains("/") {
            return Bundle.main.url(forResource: (path as NSString).deletingPathExtension,
                                   withExtension: "usdz")
        }
        return ServerConfig.shared.assetURL("/Persona/\(path)")
    }

    public var orderedStates: [String] {
        ["idle", "listening", "thinking", "speaking"].filter { usdzClips[$0] != nil }
    }
}
