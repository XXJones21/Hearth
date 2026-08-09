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

public struct PersonaVisualization: Equatable {
    public enum Kind: String {
        /// Procedural orb (Sulivan). Rendered by PersonaCanvasView.
        case sphereParticle = "sphere_particle"
        /// Character model (Selene, soon Sage). Rendered by RealityKit.
        case glbAnimated = "glb_animated"
    }

    public var kind: Kind = .sphereParticle
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

    public static func from(visualization: [String: Any]?, personaName: String) -> PersonaVisualization {
        guard let visualization else { return .fallback }
        var out = PersonaVisualization()

        if let raw = visualization["type"] as? String, let kind = Kind(rawValue: raw) {
            out.kind = kind
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
