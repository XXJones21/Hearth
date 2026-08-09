//
//  ColorHex.swift
//  Hearth
//
//  Hex strings to Color and back, for the one place the phone exchanges
//  colours with the house: `state_colors` on the persona page.
//
//  Hex is the wire format by contract. The persona file stores float triples,
//  but the server owns that conversion in both directions so no client ever
//  meets one -- which is what keeps the desktop, the phone and the Quest
//  reading the same palette back. See PersonaSurface.
//
//  HearthPalette does its own decoding from UInt32 literals and is unrelated:
//  those are compile-time constants, these are values from the server.
//

import SwiftUI

public extension Color {
    /// "#E39A5B" or "E39A5B". Returns nil rather than a default, so a
    /// malformed value from the server is visible instead of silently warm.
    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Back to "#RRGGBB" for the wire.
    ///
    /// Resolved against the LIGHT trait deliberately. A colour picked while
    /// the phone is in ember mode is still the persona's colour, not a dark
    /// variant of it, and every other client reads it back without knowing
    /// which mode it was chosen in.
    var hexString: String? {
        #if canImport(UIKit)
        let ui = UIColor(self).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let clamp = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
        #else
        return nil
        #endif
    }
}
