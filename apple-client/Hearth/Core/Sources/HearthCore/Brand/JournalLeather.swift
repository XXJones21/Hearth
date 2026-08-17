//
//  JournalLeather.swift
//  Hearth
//
//  The six leathers a journal's spine can be bound in.
//
//  Hoisted out of the phone's BookSpine so the headset's 3D books can be bound
//  in the same six. They were `private static let leathers` on a SwiftUI view,
//  which was correct while one client drew books and became a drift waiting to
//  happen the moment a second one did: a library whose spines are one set of
//  browns on a phone and another in a headset is two libraries.
//
//  Each colour is written once and decoded into both a SwiftUI `Color` and a
//  `SIMD3<Float>`, the same discipline HearthPalette uses for exactly the same
//  reason -- the flat renderer and the RealityKit one cannot drift if they read
//  the same number.
//
//  WHY IT IS THE TITLE that picks. A journal's binding should be stable across
//  launches, across clients, and across the shelf being reordered, and its
//  title is the only thing about it that never changes. Hashing it means the
//  same journal is the same colour everywhere, forever, with nothing stored.
//

import SwiftUI
import simd

public enum JournalLeather {
    /// sRGB components, as the phone's literals had them.
    private static let hexes: [SIMD3<Float>] = [
        SIMD3(0.725, 0.443, 0.290),
        SIMD3(0.659, 0.384, 0.243),
        SIMD3(0.788, 0.541, 0.333),
        SIMD3(0.557, 0.357, 0.235),
        SIMD3(0.816, 0.592, 0.388),
        SIMD3(0.612, 0.416, 0.271),
    ]

    public static var count: Int { hexes.count }

    /// The binding for a journal, by title.
    public static func scene(forTitle title: String) -> SIMD3<Float> {
        hexes[index(forTitle: title)]
    }

    /// The same binding, for a flat renderer.
    public static func color(forTitle title: String) -> Color {
        let c = scene(forTitle: title)
        return Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: 1)
    }

    /// Stable across launches and clients: a sum of the title's bytes.
    public static func index(forTitle title: String) -> Int {
        let sum = title.utf8.reduce(0) { ($0 &+ Int($1)) % 4096 }
        return sum % max(1, hexes.count)
    }

    /// The ink a title is stamped in. Pale enough to read on every leather.
    public static let letteringScene = SIMD3<Float>(1.0, 0.953, 0.894)
    public static var letteringColor: Color {
        Color(.sRGB, red: 1.0, green: 0.953, blue: 0.894, opacity: 1)
    }

    /// How thick a journal's spine is, as a fraction of a book's height.
    ///
    /// The phone's rule, in proportions rather than points: a spine is wider
    /// the more pages it holds, clamped so a one-page seedling is still a book
    /// and an epic is still shelvable. `min(46, max(19, 17 + pages * 2.2))`
    /// against a 132pt spine is where these numbers come from.
    public static func spineFraction(pages: Int) -> Float {
        let points = min(46.0, max(19.0, 17.0 + Double(pages) * 2.2))
        return Float(points / 132.0)
    }
}
