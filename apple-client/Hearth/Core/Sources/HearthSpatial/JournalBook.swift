//
//  JournalBook.swift
//  HearthSpatial
//
//  A journal as an object you can pick up, rather than a row in a list.
//
//  Procedural: a cover, a spine and a block of pages, built from boxes. No
//  modelled assets in v1, and that is a decision rather than a shortcut. The
//  orb is clean geometry and a warm palette; a photoreal leather-bound tome
//  next to it would look like it wandered in from another app. The object
//  language stays in the bead's family and the persona's colours.
//
//  WHAT IT DOES NOT OWN: the reading experience. An open book's pages are a
//  SwiftUI attachment mounted by the host, reusing JournalBookView and
//  JournalEntryView unchanged -- the same views the phone renders. This file
//  builds a thing that opens; what is written inside it is the shared surface's
//  business, and duplicating it here would be a second journal renderer to keep
//  in step with the first.
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

    private let cover: ModelEntity
    private let pages: ModelEntity

    /// Open books lie flat and face the reader; closed ones stand on the shelf.
    public private(set) var isOpen = false

    /// Where the attachment carrying the pages should sit when open, in the
    /// book's own space. The host reads this rather than guessing.
    public var pageAnchor: SIMD3<Float> { SIMD3<Float>(0, Self.height * 0.52, 0) }

    // A book's proportions, not a slab's. Roughly a hardback: taller than it
    // is wide, and thin. The first cut had these near-square and the shelf read
    // as a stack of tiles rather than a row of books.
    //
    // These are the entity's OWN units. The library panel scales the whole row
    // to fit, so what matters here is the ratio between them and the plank.
    public static let width: Float = 0.030
    public static let height: Float = 0.046
    public static let thickness: Float = 0.009

    public init(book: JournalBook, palette: PersonaPalette) {
        self.book = book
        root = Entity()
        root.name = "JournalBook.\(book.id)"

        // The cover carries the persona's colour, shaded by shelf so the four
        // shelves read as four groups without a label between them.
        var coverMaterial = PhysicallyBasedMaterial()
        coverMaterial.baseColor = .init(tint: Self.coverColor(for: book, palette: palette))
        coverMaterial.roughness = .init(floatLiteral: 0.65)
        coverMaterial.metallic = .init(floatLiteral: 0.0)

        cover = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(Self.width, Self.height, Self.thickness),
                               cornerRadius: 0.002),
            materials: [coverMaterial])
        cover.name = "cover"
        root.addChild(cover)

        // The page block, a hair smaller so the cover reads as wrapping it.
        var pageMaterial = PhysicallyBasedMaterial()
        pageMaterial.baseColor = .init(tint: Self.color(HearthPalette.Scene.cream))
        pageMaterial.roughness = .init(floatLiteral: 0.9)
        pages = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(Self.width * 0.92,
                                                  Self.height * 0.94,
                                                  Self.thickness * 0.7),
                               cornerRadius: 0.001),
            materials: [pageMaterial])
        pages.name = "pages"
        pages.position = SIMD3<Float>(0, 0, Self.thickness * 0.18)
        root.addChild(pages)

        // Gaze-and-pinch. Design section 5's first open path, and the reason it
        // exists: a person should be able to take a book down without asking
        // the house to do it for them.
        #if os(visionOS)
        root.components.set(CollisionComponent(
            shapes: [.generateBox(size: SIMD3<Float>(Self.width * 1.4,
                                                     Self.height * 1.2,
                                                     Self.thickness * 3))]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
        #endif
    }

    /// Open or close, on the hinge.
    ///
    /// The cover swings and the whole book tips toward the reader. Animated
    /// through RealityKit's own `move(to:)` rather than the behaviour
    /// director's per-frame sequencer, because this is a one-shot with a fixed
    /// destination and nothing has to compose with it.
    public func setOpen(_ open: Bool, animated: Bool = true) {
        guard open != isOpen else { return }
        isOpen = open

        let duration: TimeInterval = animated ? 0.45 : 0

        // The cover swings back on its spine edge. Rotating about the entity's
        // centre would sink half of it through the pages, so the cover is
        // offset to its hinge and rotated there.
        let coverAngle: Float = open ? -.pi * 0.78 : 0
        var coverTransform = Transform()
        coverTransform.rotation = simd_quatf(angle: coverAngle, axis: SIMD3<Float>(0, 1, 0))
        // Hinge at the spine: shift out, turn, shift back.
        coverTransform.translation = SIMD3<Float>(
            -Self.width * 0.5 + cos(coverAngle) * Self.width * 0.5,
            0,
            sin(coverAngle) * Self.width * 0.5)
        cover.move(to: coverTransform, relativeTo: root, duration: duration)

        // The book itself tips flat and lifts, so an open book reads as being
        // held out to you rather than still filed on the shelf.
        var bookTransform = Transform()
        bookTransform.rotation = open
            ? simd_quatf(angle: -.pi * 0.32, axis: SIMD3<Float>(1, 0, 0))
            : simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
        bookTransform.translation = open ? SIMD3<Float>(0, 0.03, 0.05) : .zero
        root.move(to: bookTransform, relativeTo: root.parent, duration: duration)
    }

    /// Re-tint on a palette swap, so a persona change reaches the shelf.
    public func apply(palette: PersonaPalette) {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: Self.coverColor(for: book, palette: palette))
        material.roughness = .init(floatLiteral: 0.65)
        material.metallic = .init(floatLiteral: 0.0)
        cover.model?.materials = [material]
    }

    // MARK: - Colour

    /// The persona's colour, shifted per shelf.
    ///
    /// Not four arbitrary colours: the persona's own palette supplies the
    /// family and the shelf picks a member of it, so a house with a different
    /// persona gets a different library rather than the same one repainted.
    private static func coverColor(for book: JournalBook, palette: PersonaPalette) -> UIColor {
        let base: SIMD3<Float>
        switch book.shelf {
        case .heart:    base = palette.speaking
        case .life:     base = palette.listening
        case .project:  base = palette.sphere
        case .seedling: base = palette.thinking
        }
        // A seedling is barely written; it reads paler, which is the shelf's
        // whole meaning made visible.
        let t: Float = book.isSeedling ? 0.55 : 0.18
        return color(base * (1 - t) + HearthPalette.Scene.cream * t)
    }

    private static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
}

// MARK: - The shelf plank

/// One shelf: a plank for books to stand on.
///
/// Separate from the books so a row can be laid out and scaled as one thing.
/// Plain geometry, warm wood from the brand's own journal tokens -- the same
/// two colours the phone's journal covers use, so the library reads as the same
/// library in both places.
@MainActor
public enum JournalShelfPlank {
    /// A plank `width` long, sized in the book's own units.
    public static func make(width: Float) -> Entity {
        let thickness: Float = JournalBookEntity.thickness * 1.6
        let depth: Float = JournalBookEntity.thickness * 4.2

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color(HearthPalette.Scene.roast))
        material.roughness = .init(floatLiteral: 0.85)
        material.metallic = .init(floatLiteral: 0.0)

        let plank = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(width, thickness, depth),
                               cornerRadius: 0.0012),
            materials: [material])
        plank.name = "shelf.plank"
        // Books stand ON it, so the plank sits below their origin by half a
        // book plus half a plank.
        plank.position = SIMD3<Float>(0, -(JournalBookEntity.height + thickness) * 0.5, 0)
        return plank
    }

    private static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
}
