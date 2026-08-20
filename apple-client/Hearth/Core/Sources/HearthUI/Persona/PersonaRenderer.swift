//
//  PersonaRenderer.swift
//  HearthUI
//
//  Which drawing the phone uses for a persona. INVESTIGATION SCAFFOLDING, and
//  it leaves when the fire becomes the config-driven default.
//
//  It lives in the package rather than the app target because both ends need
//  it: the stage picks a renderer from it and the settings surface sets it, and
//  the settings surface is shared code that cannot see the app target.
//
//  The switch started on the stage, where an A/B belongs -- one you have to go
//  and find is one nobody runs twice. With the comparison decided it moves into
//  Settings, because what is left is not a choice anybody makes twice a day. It
//  is a way to hold the new flame against the persona it replaces while the
//  flame is still being tuned.
//

import Foundation

public enum PersonaRenderer: String, CaseIterable, Identifiable, Sendable {
    /// Whatever the persona's own config asks for -- for Sulivan today, the
    /// drawn face. The control, not a candidate.
    case shipped
    /// The flame drawn with vector primitives in a SwiftUI Canvas.
    ///
    /// The decision, taken 2026-08-20. A RealityKit route was built, looked
    /// excellent, and lost on the two things that decide a phone: it cost more
    /// (18.2ms against 16.7ms) and it would have been a second persona renderer
    /// on a platform that already needs this one for widgets. One
    /// implementation beats a better-looking second one.
    case canvasFire

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .shipped:    return "Shipped"
        case .canvasFire: return "Fire"
        }
    }

    public static let storageKey = "hearth.investigate.personaRenderer"
}
