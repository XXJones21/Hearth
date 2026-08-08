//
//  HearthPalette.swift
//  Hearth
//
//  Single source of color truth for the Hearth brand (Direction B) across the
//  iOS and visionOS builds of the Hearth target.
//
//  Values transcribed from hearth-pitch/brand-direction.md (v1, 2026-07-21) and
//  tasks/hearth-ios-handoff.md. Do not invent shades; add tokens here.
//
//  Brand rules (non-negotiable):
//    - LIGHT-FIRST and warm. `cream` background, `fluff` surfaces.
//    - `roast` on `cream`/`fluff` is the ONLY body-text pairing.
//    - `fennec`/`honey` are fills, accents, and iconography -- NEVER text on
//      light surfaces (label them with `roast`).
//    - "ember" is the warm-dark variant: "the room after the fire burns low".
//
//  Each token is defined once as a 24-bit hex literal and decoded into both a
//  SwiftUI `Color` (UI) and a `SIMD3<Float>` (RealityKit scene) so the two
//  renderers can never drift. The normalized components match the renderer's
//  existing sRGB convention (hex / 255), i.e. the "Linear RGB" column of the
//  handoff table.
//
//  EMBER MODE. Every UI token is a DYNAMIC color: one hex for light, one for
//  ember, resolved per trait collection. Nothing outside this file branches on
//  appearance -- a view that says `HearthPalette.cream` gets the right surface
//  in either mode for free. Ember values are the desktop's, verbatim from
//  `hearth-client/src/styles/globals.css` (`.ember`), so the two clients cannot
//  drift on what the dark room looks like.
//
//  Only SURFACES and INK flip. fennec, ember and honey are the fire itself and
//  stay exactly as they are in both modes -- which is also why `Scene` (the
//  RealityKit orb) has no dark variant: the orb is warm at midnight too.
//
//  iOS follows the OS here rather than offering a toggle (desktop owns it in
//  Settings > Appearance because it has the `inapp-theme` capability and iOS
//  does not; see ClientProfile).
//

import SwiftUI
import simd
#if canImport(UIKit)
import UIKit
#endif

public enum HearthPalette {

    // MARK: - Core tokens (hex — the single source)

    private enum Hex {
        static let cream:  UInt32 = 0xFAF4EA   // mascot chest fluff -- app background
        static let fluff:  UInt32 = 0xFFFFFF   // white fur -- cards / surfaces
        static let fennec: UInt32 = 0xE39A5B   // body fur -- primary accent, the orb
        static let ember:  UInt32 = 0xC97F45   // shaded fur -- hover/pressed, emphasis
        static let honey:  UInt32 = 0xFFB84D   // pitch amber -- highlights, glows, fills
        static let roast:  UInt32 = 0x3B2B20   // eyes / ear tips -- primary text (ink)
        static let fawn:   UInt32 = 0x8C7A66   // muted fur shadow -- secondary text
        static let linen:  UInt32 = 0xEFE6D8   // dividers, recessed tracks

        // Derived tints (fills)
        static let parchment:  UInt32 = 0xFBF3E7
        static let glowtint:   UInt32 = 0xFDF4E4
        static let bubble:     UInt32 = 0xF6E3CB
        static let bubbleLine: UInt32 = 0xEDD5B4
        static let tab:        UInt32 = 0xF8E2C4

        // Warning ink and its wash: the "needs a credential" note in Apps and
        // any other row reporting something unfinished. Warm enough to belong
        // to the hearth rather than reading as a system error.
        static let clay:       UInt32 = 0x8A3D2A
        static let clayWash:   UInt32 = 0xFBF1EC
        static let clayLine:   UInt32 = 0xE8CFC2

        /// The cool tile in Apps, for a CLI. The only deliberately unwarm
        /// colour in the palette: a command line is not part of the hearth.
        static let slate:      UInt32 = 0x6E7B8B

        /// "This is live and healthy" -- a connected device, a reachable
        /// bridge. Green enough to read as good, muted enough to sit in a
        /// warm palette without shouting.
        static let sage:       UInt32 = 0x7C8F72

        // Soft-shadow ink (shadow-soft: rgb(97,63,29) @ 0.07 on light surfaces)
        static let shadow:      UInt32 = 0x613F1D
    }

    /// Ember mode -- the warm dark variant. Values are the desktop's `.ember`
    /// block, verbatim, so the clients cannot drift.
    private enum EmberHex {
        static let cream:      UInt32 = 0x241B14   // app background
        static let fluff:      UInt32 = 0x2C221A   // raised surfaces / cards
        static let roast:      UInt32 = 0xF3E9DC   // ink
        static let fawn:       UInt32 = 0xB3A18C   // secondary ink
        static let linen:      UInt32 = 0x3A2E24   // dividers, recessed tracks
        static let parchment:  UInt32 = 0x2A211A
        static let glowtint:   UInt32 = 0x33271C
        static let bubble:     UInt32 = 0x3A2B1E
        static let bubbleLine: UInt32 = 0x4A3729
        static let tab:        UInt32 = 0x3E2F22

        /// Clay has to lift off a dark surface rather than sink into it, so
        /// ember mode takes a brighter ink over a much darker wash.
        static let clay:       UInt32 = 0xE09578
        static let clayWash:   UInt32 = 0x3A2620
        static let clayLine:   UInt32 = 0x5C3A2C
        static let slate:      UInt32 = 0x8593A3
        static let sage:       UInt32 = 0x9DB093

        /// The card shadow reads as nothing on a dark surface; a faint warm
        /// lift beats an invisible one.
        static let shadow:     UInt32 = 0x000000
    }

    // MARK: - SwiftUI colors (UI surfaces, text, chrome)
    //
    // Surfaces and ink flip with the system appearance. The three fire
    // accents do not.

    public static let cream      = color(Hex.cream, EmberHex.cream)
    public static let fluff      = color(Hex.fluff, EmberHex.fluff)
    public static let roast      = color(Hex.roast, EmberHex.roast)
    public static let fawn       = color(Hex.fawn, EmberHex.fawn)
    public static let linen      = color(Hex.linen, EmberHex.linen)

    public static let parchment  = color(Hex.parchment, EmberHex.parchment)
    public static let glowtint   = color(Hex.glowtint, EmberHex.glowtint)
    public static let bubble     = color(Hex.bubble, EmberHex.bubble)
    public static let bubbleLine = color(Hex.bubbleLine, EmberHex.bubbleLine)
    public static let tab        = color(Hex.tab, EmberHex.tab)

    public static let clay       = color(Hex.clay, EmberHex.clay)
    public static let slate      = color(Hex.slate, EmberHex.slate)
    public static let sage       = color(Hex.sage, EmberHex.sage)
    public static let clayWash   = color(Hex.clayWash, EmberHex.clayWash)
    public static let clayLine   = color(Hex.clayLine, EmberHex.clayLine)

    public static let shadow     = color(Hex.shadow, EmberHex.shadow)

    /// The fire: identical in both modes.
    public static let fennec     = color(Hex.fennec)
    public static let ember      = color(Hex.ember)
    public static let honey      = color(Hex.honey)

    /// True when the app is rendering ember mode. Only for the rare case where
    /// a token cannot express the difference (a shadow opacity, a blend
    /// amount); prefer a dynamic token over asking this.
    static var isEmber: Bool {
        #if canImport(UIKit)
        return UITraitCollection.current.userInterfaceStyle == .dark
        #else
        return false
        #endif
    }

    // MARK: - Persona attribution (timeline initial-circle nodes)

    /// Node/accent color for each speaker on the feed rail.
    static func speaker(_ name: String) -> Color {
        switch name.lowercased() {
        case "you", "user":   return linen
        case "sulivan":       return fennec
        case "selene":        return honey
        case "mentat":        return ember
        default:              return fawn
        }
    }

    // MARK: - RealityKit / scene tokens (SIMD3<Float>, sRGB components 0...1)

    enum Scene {
        static let cream  = simd(Hex.cream)
        static let fluff  = simd(Hex.fluff)
        static let fennec = simd(Hex.fennec)
        static let ember  = simd(Hex.ember)
        static let honey  = simd(Hex.honey)
        static let roast  = simd(Hex.roast)
        static let linen  = simd(Hex.linen)
    }

    // MARK: - Decoders (one hex -> Color and SIMD3<Float>)

    private static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (
            Double((hex >> 16) & 0xFF) / 255.0,
            Double((hex >> 8) & 0xFF) / 255.0,
            Double(hex & 0xFF) / 255.0
        )
    }

    private static func color(_ hex: UInt32) -> Color {
        let c = components(hex)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1.0)
    }

    /// A token that resolves per appearance. Backed by a dynamic UIColor so it
    /// re-resolves whenever the trait collection changes -- no view has to
    /// observe `colorScheme` or re-read anything.
    private static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let c = components(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
        })
        #else
        return color(light)
        #endif
    }

    private static func simd(_ hex: UInt32) -> SIMD3<Float> {
        let c = components(hex)
        return SIMD3<Float>(Float(c.r), Float(c.g), Float(c.b))
    }
}

// MARK: - Hearth view helpers

extension View {
    /// Hearth `shadow-soft`: a low, warm card shadow (0 2px 10px rgb(97,63,29)/0.07).
    /// Ember mode leans on it harder -- a 7% warm shadow is invisible against
    /// a dark surface, and the card edges are what separate the rooms.
    func hearthSoftShadow() -> some View {
        shadow(color: HearthPalette.shadow.opacity(HearthPalette.isEmber ? 0.35 : 0.07),
               radius: 5, x: 0, y: 2)
    }
}

extension Color {
    /// Linear blend toward `other` by `amount` (0...1), via UIColor components.
    /// Used for the persona node's lightened radial-gradient inner stop.
    func mixed(with other: Color, amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        let a = rgba, b = other.rgba
        return Color(red: a.r + (b.r - a.r) * t,
                     green: a.g + (b.g - a.g) * t,
                     blue: a.b + (b.b - a.b) * t)
    }
}
