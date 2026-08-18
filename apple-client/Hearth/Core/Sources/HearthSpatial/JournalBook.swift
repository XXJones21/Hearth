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

    /// A book's height, IN METRES AND AT LIFE SIZE. Everything else in the
    /// library is a proportion of this, exactly as the phone's spine is a
    /// proportion of its 132pt height.
    ///
    /// A large Moleskine: 21cm by 13cm. Twice this file has claimed those
    /// proportions and set numbers far short of them -- 0.046, then 0.060, both
    /// about the height of a thumb. RealityKit's unit IS the metre, so a book
    /// that should be 0.21 was authored at a quarter of that and every derived
    /// number, the spine lettering worst of all, came out a quarter too small
    /// with it.
    ///
    /// AUTHOR AT LIFE SIZE, PRESENT AT ANY SIZE. Nothing in the library scales
    /// itself now; the library's root does, so `scale = 1` is a real bookcase
    /// and the persona's investigation prop is the same tree at 0.10. Anything
    /// that hard-codes a smaller number here takes that choice away again.
    public static let height: Float = 0.21
    /// How far a book reaches back into the shelf: its width, closed.
    public static let depth: Float = 0.13

    /// How thick THIS book is, from its page count.
    public var thickness: Float { Self.height * JournalLeather.spineFraction(pages: book.pages) }

    /// - Parameter interactive: give the book a collision shape and an input
    ///   target. False for the persona's investigation prop, which is scenery:
    ///   a person reaching past the orb to pinch a 2cm book the house is
    ///   reading would be reaching for something that is about to vanish.
    public init(book: JournalBook, palette: PersonaPalette, interactive: Bool = true) {
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
                               cornerRadius: Self.height * 0.002),
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
        if interactive {
            root.components.set(CollisionComponent(
                shapes: [.generateBox(size: SIMD3<Float>(width, Self.height, Self.depth))]))
            root.components.set(InputTargetComponent())
            root.components.set(HoverEffectComponent())
        }
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
            extrusionDepth: Self.height * 0.001,
            // Derived from the book, never a literal: lettering that does not
            // move with the geometry is the bug this file has already had.
            font: .systemFont(ofSize: CGFloat(Self.height * 0.052), weight: .semibold),
            containerFrame: CGRect(x: 0, y: 0, width: CGFloat(usable), height: CGFloat(width)),
            alignment: .left,
            lineBreakMode: .byTruncatingTail)

        var ink = UnlitMaterial()
        ink.color = .init(tint: Self.color(JournalLeather.letteringScene))

        // CENTRED ON THE SPINE, measured rather than guessed.
        //
        // `generateText` lays out from its own baseline-left origin, so a
        // rotated label sits wherever that origin lands -- which for a thick
        // book put the lettering off the leather entirely. The first cut nudged
        // it by a fraction of the book's WIDTH, which cannot be right for both
        // a thin seedling and a fat archive.
        //
        // The mesh knows its own extent. Centre the glyphs on their own origin
        // first, then the wrapper's placement is exact for any thickness: the
        // label is on the spine because it is put where the spine is.
        let glyphs = ModelEntity(mesh: mesh, materials: [ink])
        let bounds = mesh.bounds
        glyphs.position = -bounds.center

        let label = Entity()
        label.name = "title"
        label.addChild(glyphs)
        // Turn it up the spine: bottom-to-top, as almost every
        // English-language spine reads and as the phone's -90 degrees does.
        label.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        // Just proud of the leather, dead centre of the face.
        label.position = SIMD3<Float>(0, 0, Self.depth * 0.5 + Self.height * 0.002)
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
