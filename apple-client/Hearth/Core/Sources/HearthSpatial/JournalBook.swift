//
//  JournalBook.swift
//  HearthSpatial
//
//  A journal as an object on a shelf: spine out, bound in leather, its title
//  stamped up the spine.
//
//  This is the phone's `BookSpine` in three dimensions, and it is a
//  reconstruction rather than an invention. Every rule comes from that view --
//  the spine gets wider the more pages it holds, the leather is one of six
//  picked by hashing the title, the lettering is the same pale cream, there is
//  a highlight down the hinge edge. Those decisions were made once, for a
//  library that already reads well; the headset's job is to render them with
//  boxes instead of rounded rectangles, not to have opinions about them.
//
//  WHY SPINE OUT. The first cut stood the books cover-forward, which is how a
//  shop displays three featured titles and not how a library holds two hundred.
//  Cover-out costs six times the shelf width per book and tells you nothing the
//  spine does not -- and it left every book unlabelled, because the cover has
//  no text on it. A shelf is spines. The phone knows this: its `heartDisplay`
//  turns exactly the living volumes face-out and every other room is spines.
//
//  WHAT IT DOES NOT OWN: the reading experience. An opened journal is
//  JournalBookView, the view the phone renders, mounted by the host as a
//  SwiftUI attachment. Duplicating it here would be a second journal renderer
//  to keep in step with the first.
//

import Foundation
import RealityKit
import simd
import HearthCore

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class JournalBookEntity {
    /// What a host adds to a shelf.
    public let root: Entity

    /// The journal this stands for.
    public let book: JournalBook

    private let spine: ModelEntity

    /// A book's height on the shelf, in the library's own units. Everything
    /// else is a proportion of this, exactly as the phone's spine is a
    /// proportion of its 132pt height.
    public static let height: Float = 0.046
    /// How far a book reaches back into the shelf.
    public static let depth: Float = 0.034

    /// How thick THIS book is, from its page count.
    public var thickness: Float { Self.height * JournalLeather.spineFraction(pages: book.pages) }

    public init(book: JournalBook, palette: PersonaPalette) {
        self.book = book
        root = Entity()
        root.name = "JournalBook.\(book.id)"

        let width = Self.height * JournalLeather.spineFraction(pages: book.pages)

        // The binding. `PersonaPalette` deliberately does NOT tint this: a
        // library is bound in leather, not in the persona's accent, and the
        // phone's shelf makes the same call. The persona colours the orb; the
        // house colours its books.
        var leather = PhysicallyBasedMaterial()
        leather.baseColor = .init(tint: Self.color(JournalLeather.scene(forTitle: book.title)))
        leather.roughness = .init(floatLiteral: 0.78)
        leather.metallic = .init(floatLiteral: 0.0)

        spine = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(width, Self.height, Self.depth),
                               cornerRadius: width * 0.14),
            materials: [leather])
        spine.name = "spine"
        root.addChild(spine)

        // The pale block of pages, showing at the fore edge -- the side away
        // from the hinge. Without it a spine-out book is a coloured brick.
        var paper = PhysicallyBasedMaterial()
        paper.baseColor = .init(tint: Self.color(HearthPalette.Scene.cream))
        paper.roughness = .init(floatLiteral: 0.95)
        let pages = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(width * 0.72,
                                                  Self.height * 0.92,
                                                  Self.depth * 0.94),
                               cornerRadius: 0.0004),
            materials: [paper])
        pages.name = "pages"
        // Pushed back so it peeks out behind the leather rather than through it.
        pages.position = SIMD3<Float>(0, 0, -Self.depth * 0.06)
        root.addChild(pages)

        addTitle(width: width)

        // Gaze-and-pinch, and the collision box is the SPINE and nothing but
        // the spine -- the phone's comment says the same thing for the same
        // reason. A generous box on a shelf of thin books means the wrong book
        // opens.
        #if os(visionOS)
        root.components.set(CollisionComponent(
            shapes: [.generateBox(size: SIMD3<Float>(width, Self.height, Self.depth))]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
        #endif
    }

    /// The title, stamped up the spine.
    ///
    /// Rotated a quarter turn so it reads bottom-to-top, which is what the
    /// phone does with `rotationEffect(.degrees(-90))` and what almost every
    /// English-language spine does in life. Truncated by the container frame
    /// rather than by counting characters: a long title on a thin spine is the
    /// normal case, not the exception.
    private func addTitle(width: Float) {
        let usable = Self.height * 0.86
        let mesh = MeshResource.generateText(
            book.title,
            extrusionDepth: 0.0002,
            font: .systemFont(ofSize: 0.0092, weight: .semibold),
            containerFrame: CGRect(x: 0, y: 0, width: CGFloat(usable), height: CGFloat(width)),
            alignment: .left,
            lineBreakMode: .byTruncatingTail)

        var ink = UnlitMaterial()
        ink.color = .init(tint: Self.color(JournalLeather.letteringScene))

        let label = ModelEntity(mesh: mesh, materials: [ink])
        label.name = "title"
        // Turn it up the spine, then push it just clear of the leather.
        label.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        // generateText lays out from its own origin, so the rotated text has to
        // be walked back into the middle of the face by hand.
        label.position = SIMD3<Float>(width * 0.30,
                                      -usable * 0.5,
                                      Self.depth * 0.5 + 0.0004)
        root.addChild(label)
    }

    /// Re-tint on a palette swap.
    ///
    /// A no-op for the binding, which is the persona-independent part, and kept
    /// so hosts can call it uniformly without knowing that.
    public func apply(palette: PersonaPalette) {}

    private static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
}

// MARK: - The shelf board

/// One shelf board, the phone's `ShelfBoard` given a third dimension.
@MainActor
public enum JournalShelfPlank {
    public static func make(width: Float) -> Entity {
        let thickness: Float = JournalBookEntity.height * 0.10
        let depth: Float = JournalBookEntity.depth * 1.15

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color(HearthPalette.Scene.roast))
        material.roughness = .init(floatLiteral: 0.85)
        material.metallic = .init(floatLiteral: 0.0)

        let plank = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(width, thickness, depth),
                               cornerRadius: thickness * 0.25),
            materials: [material])
        plank.name = "shelf.board"
        // Books stand ON it.
        plank.position = SIMD3<Float>(0, -(JournalBookEntity.height + thickness) * 0.5, 0)
        return plank
    }

    private static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
}
