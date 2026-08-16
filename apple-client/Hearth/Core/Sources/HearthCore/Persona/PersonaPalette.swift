//
//  PersonaPalette.swift
//  Hearth  (shared by the app target AND the Hearth WidgetExtension target)
//
//  The persona's orb colours, data-driven from its config. A persona owns its
//  palette server-side (Persona/<name>/<name>.json -> visualization.sphere.color,
//  particle_system.color, state_colors); the server forwards the whole
//  `visualization` block verbatim via public_config() over the `persona_config`
//  WebSocket message, so every client reads the SAME contract. This struct
//  decodes that payload. `HearthPalette` is only the warm fallback for personas
//  that carry no palette (and for the widgets, which have no live connection).
//
//  Canonical values are SIMD3<Float> (sRGB components, for the RealityKit orb);
//  the `*Color` accessors bridge to SwiftUI Color for the 2D PersonaOrb canvas.
//

import SwiftUI
import simd

public struct PersonaPalette: Equatable {
    var sphere: SIMD3<Float>       // core bead body
    var particle: SIMD3<Float>     // orbiting particle field
    var idle: SIMD3<Float>         // per-state glow accents
    var listening: SIMD3<Float>
    var thinking: SIMD3<Float>
    var speaking: SIMD3<Float>

    // MARK: - SwiftUI Color accessors (2D canvas + widgets)

    var sphereColor: Color    { Self.color(sphere) }
    var particleColor: Color  { Self.color(particle) }
    var idleColor: Color      { Self.color(idle) }
    var listeningColor: Color { Self.color(listening) }
    var thinkingColor: Color  { Self.color(thinking) }
    var speakingColor: Color  { Self.color(speaking) }

    /// The glow accent for a turn state (mirrors RealityKitSceneManager).
    func glow(for state: HearthState) -> SIMD3<Float> {
        switch state {
        case .LISTENING: return listening
        case .THINKING:  return thinking
        case .SPEAKING:  return speaking
        default:         return idle   // LOADING / IDLE
        }
    }

    // MARK: - Defaults

    /// Warm Hearth brand colours. The base a SERVER payload fills in over: a
    /// persona that ships no palette gets these, not another persona's.
    /// `thinking` interpolates fennec->ember, matching the config value.
    static let warmDefaults = PersonaPalette(
        sphere:    HearthPalette.Scene.fennec,
        particle:  HearthPalette.Scene.honey,
        idle:      HearthPalette.Scene.fennec,
        listening: HearthPalette.Scene.honey,
        thinking:  (HearthPalette.Scene.fennec + HearthPalette.Scene.ember) * 0.5,
        speaking:  HearthPalette.Scene.ember
    )

    /// What a client with NO connection shows: Sulivan, decoded from the JSON
    /// bundled beside this code, by the same decoder that handles the wire
    /// payload. Falls back to the brand colours only if the resource is missing.
    ///
    /// This is the difference between a first run that renders the real persona
    /// with nothing listening on any port, and one that renders a palette
    /// default and looks deliberate. The widgets get it too, which is why they
    /// stop being a third copy of the palette.
    public static let fallback: PersonaPalette = {
        guard let visualization = BundledPersona.sulivan?.visualization else {
            return warmDefaults
        }
        return from(visualization: visualization)
    }()

    // MARK: - Decode from the persona_config `visualization` payload

    /// Build from the server's `visualization` block. Any missing field keeps
    /// the fallback value, so partial or legacy configs are safe (server wins
    /// where it provides a colour; warm defaults everywhere else).
    static func from(visualization: [String: Any]?) -> PersonaPalette {
        guard let vis = visualization else { return .warmDefaults }
        var p = PersonaPalette.warmDefaults

        if let sphere = vis["sphere"] as? [String: Any], let c = rgb(sphere["color"]) {
            p.sphere = c
        }
        if let ps = vis["particle_system"] as? [String: Any], let c = rgb(ps["color"]) {
            p.particle = c
        }
        if let states = vis["state_colors"] as? [String: Any] {
            if let c = rgb(states["idle"])      { p.idle = c }
            if let c = rgb(states["listening"]) { p.listening = c }
            if let c = rgb(states["thinking"])  { p.thinking = c }
            if let c = rgb(states["speaking"])  { p.speaking = c }
        }
        return p
    }

    // MARK: - Helpers

    private static func color(_ c: SIMD3<Float>) -> Color {
        Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: 1)
    }

    /// Read an `{r,g,b}` colour object (alpha ignored -- the orb bead is solid).
    private static func rgb(_ any: Any?) -> SIMD3<Float>? {
        guard let d = any as? [String: Any],
              let r = num(d["r"]), let g = num(d["g"]), let b = num(d["b"]) else { return nil }
        return SIMD3<Float>(r, g, b)
    }

    /// The module's one JSON numeric coercion, narrowed to the Float the orb
    /// colours are kept in. Was a second copy of `personaNum` until the face
    /// needed the same tolerance for its geometry.
    private static func num(_ any: Any?) -> Float? {
        personaNum(any).map(Float.init)
    }
}
