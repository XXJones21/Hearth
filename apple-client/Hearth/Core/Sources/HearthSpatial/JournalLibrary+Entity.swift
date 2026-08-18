//
//  JournalLibrary+Entity.swift
//  HearthSpatial
//
//  The library as one entity: shelves of spine-out books that scroll.
//
//  An ENTITY rather than a window, and that was learned the expensive way. The
//  books were tried loose in the stage (they floated, with nothing to stand on),
//  then in a RealityView nested inside an attachment (an attachment is a SwiftUI
//  view rendered onto a plane; three dimensions do not fit in it), then in a
//  volumetric window of their own -- which worked, and obscured the main volume,
//  because a second volume in the Shared Space sits in front of the first. A
//  library you cannot see past is not a library you want open while talking to
//  the house.
//
//  So it lives in the main volume, in the centre slot the orb slides away from.
//  One window, one scene, and the library is simply part of it.
//
//  THE LAYOUT IS THE PHONE'S. Rooms in Selene's locked order, each a row of
//  spines on a board: the Curator's Alcove, the Active Forge, the Glass
//  Conservatory. The Heart stands face-out on the phone and stands with the
//  others here, because a volume shows one shelf at a time and a mixed row of
//  orientations reads as a mistake rather than as emphasis.
//

import Foundation
import RealityKit
import simd
import HearthCore

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class JournalLibraryEntity {
    /// What a host adds to its scene.
    public let root = Entity()

    /// The part that moves when scrolled. Separate from `root` so the host can
    /// place the library without fighting the scroll offset.
    private let scroller = Entity()

    private var booksByID: [String: JournalBookEntity] = [:]

    /// One of Selene's rooms, and the board its label hangs over.
    ///
    /// The labels are the phone's, verbatim -- "The Curator's Alcove, the
    /// person before the works" -- because they are the library's own voice and
    /// a headset paraphrasing them would be a second library speaking
    /// differently about the same books.
    public struct Room: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let caption: String
        /// Where its label belongs, in the scroller's space.
        public let anchor: SIMD3<Float>
    }

    /// The rooms laid out, top to bottom.
    public private(set) var rooms: [Room] = []

    /// Metres between one board and the next.
    private let shelfPitch: Float = JournalBookEntity.height * 1.75
    /// Metres of gap between neighbouring spines. The phone uses 9pt against a
    /// 132pt spine; this is that ratio.
    private let spineGap: Float = JournalBookEntity.height * 0.068
    /// How many boards are visible before the rest have to be scrolled to.
    private let visibleRows: Float = 3

    /// How far the shelves can travel. Zero when everything already fits.
    public private(set) var maxScroll: Float = 0

    /// Whether a person can touch this library.
    ///
    /// One flag, two libraries. The life-size one a person opens gets collision
    /// shapes and scrolling; the persona's investigation prop gets neither, so
    /// a drag never finds it, a pinch never opens a book, and it cannot be
    /// scrolled away from the shelf the orb is reading.
    public let interactive: Bool

    public init(interactive: Bool = true) {
        self.interactive = interactive
        root.name = interactive ? "JournalLibrary" : "JournalLibrary.prop"
        root.addChild(scroller)
    }

    /// How far down the library is scrolled, in metres. Clamped.
    public var scroll: Float = 0 {
        didSet {
            guard interactive else { return }
            scroller.position.y = min(maxScroll, max(0, scroll))
        }
    }

    /// Rebuild from the house's shelves.
    ///
    /// Rooms in the phone's order, so a person who knows the library on their
    /// phone finds it laid out the same way here. A room with no books is
    /// simply absent rather than an empty board, which is what the phone does
    /// too.
    public func apply(heart: [JournalBook],
                      life: [JournalBook],
                      projects: [JournalBook],
                      seedlings: [JournalBook],
                      palette: PersonaPalette) {
        for child in scroller.children.map({ $0 }) { child.removeFromParent() }
        booksByID.removeAll()

        rooms = []
        var row = 0

        // The masthead sits above everything, a room's worth of gap up.
        scroller.addChild(Self.text("Journal", size: JournalBookEntity.height * 0.115,
                                    at: SIMD3<Float>(-boardWidth * 0.5, labelRise, 0)))
        scroller.addChild(Self.text("kept by Selene", size: JournalBookEntity.height * 0.062,
                                    at: SIMD3<Float>(-boardWidth * 0.5,
                                                     labelRise - JournalBookEntity.height * 0.15, 0),
                                    muted: true))
        row = 1

        for (books, label, caption) in Self.roomOrder(heart: heart, life: life,
                                                      projects: projects, seedlings: seedlings) {
            let labelY = -Float(row) * shelfPitch + labelRise
            rooms.append(Room(id: label,
                              label: label,
                              caption: caption,
                              anchor: SIMD3<Float>(0, labelY, 0)))
            // GEOMETRY, not a SwiftUI attachment. An attachment renders in
            // points and would need its own scale factor reconciled against the
            // library's metres -- which is exactly the mismatch that left these
            // labels invisible on the device, and which would break again the
            // moment the library is presented at any size but one. Text in the
            // tree scales with the tree.
            scroller.addChild(Self.text(label, size: JournalBookEntity.height * 0.072,
                                        at: SIMD3<Float>(-boardWidth * 0.5, labelY, 0)))
            scroller.addChild(Self.text(caption, size: JournalBookEntity.height * 0.048,
                                        at: SIMD3<Float>(-boardWidth * 0.5,
                                                         labelY - JournalBookEntity.height * 0.095, 0),
                                        muted: true))
            // A room longer than a board wraps onto the next one rather than
            // running off the side: there is no horizontal scroll here, because
            // a volume scrolls one way and asking it to do both is how a person
            // loses a shelf.
            for chunk in stride(from: 0, to: books.count, by: booksPerBoard) {
                let slice = Array(books[chunk..<min(chunk + booksPerBoard, books.count)])
                scroller.addChild(board(slice, palette: palette, atRow: row))
                row += 1
            }
        }

        maxScroll = max(0, (Float(row) - visibleRows) * shelfPitch)
        scroll = 0
    }

    private let booksPerBoard = 8

    /// How far a label floats above the books it names.
    private var labelRise: Float { JournalBookEntity.height * 0.78 }

    /// Selene's locked order, with the phone's own words for each room. Empty
    /// rooms are absent rather than shown as an empty board, which is what the
    /// phone does too.
    private static func roomOrder(heart: [JournalBook],
                                  life: [JournalBook],
                                  projects: [JournalBook],
                                  seedlings: [JournalBook]) -> [([JournalBook], String, String)] {
        [
            (heart, "The Heart of the Library", "on display, the volumes that live and grow"),
            (life, "The Curator's Alcove", "the person before the works"),
            (projects, "The Active Forge", "works in motion"),
            (seedlings, "The Glass Conservatory", "seedlings, one page each"),
        ].filter { !$0.0.isEmpty }
    }

    /// Where a label should hang, once the library has been scrolled.
    ///
    /// Labels are parented to the scroller like the boards, so they travel with
    /// the shelves they name rather than sitting still while the books move
    /// past -- which would be a caption for whatever happened to be underneath.
    public var scrollerEntity: Entity { scroller }

    /// Every board is the SAME width, and books stand from its left edge.
    ///
    /// The first cut sized each board to its own row and centred it, which
    /// turned a bookcase into a staircase: a three-book row and a seven-book
    /// row had different widths and different centres, so the shelves cascaded
    /// down and to one side. A bookcase has one carcass. Books lean left
    /// against it and the empty end of a short shelf is simply empty, which is
    /// what a real shelf looks like and what the phone's left-aligned rails
    /// already do.
    private func board(_ books: [JournalBook],
                       palette: PersonaPalette,
                       atRow row: Int) -> Entity {
        let shelf = Entity()
        shelf.position = SIMD3<Float>(0, -Float(row) * shelfPitch, 0)

        // Spines left to right, each taking its own thickness. Books are not
        // evenly spaced because books are not evenly thick, which is most of
        // what makes a shelf look like a shelf.
        var x = -boardWidth * 0.5 + spineGap
        for book in books {
            let entity = JournalBookEntity(book: book, palette: palette,
                                           interactive: interactive)
            x += entity.thickness * 0.5
            entity.root.position = SIMD3<Float>(x, 0, 0)
            x += entity.thickness * 0.5 + spineGap
            shelf.addChild(entity.root)
            booksByID[entity.book.id] = entity
        }

        shelf.addChild(JournalShelfPlank.make(width: boardWidth))
        return shelf
    }

    /// The carcass width: what eight average spines and their gaps come to.
    ///
    /// Fixed rather than measured, because a board that resized itself to its
    /// contents is the staircase all over again.
    private var boardWidth: Float {
        Float(booksPerBoard) * (JournalBookEntity.height * 0.24 + spineGap) + spineGap
    }

    /// One line of text as geometry, left-aligned at `position`.
    ///
    /// Unlit so it reads at any light level, and sized in the library's own
    /// units so it scales with everything else.
    private static func text(_ string: String,
                             size: Float,
                             at position: SIMD3<Float>,
                             muted: Bool = false) -> Entity {
        let mesh = MeshResource.generateText(
            string,
            extrusionDepth: size * 0.02,
            font: .systemFont(ofSize: CGFloat(size), weight: muted ? .regular : .semibold),
            containerFrame: .zero,
            alignment: .left,
            lineBreakMode: .byTruncatingTail)

        var ink = UnlitMaterial()
        ink.color = .init(tint: color(muted ? HearthPalette.Scene.fluff : HearthPalette.Scene.cream))

        let entity = ModelEntity(mesh: mesh, materials: [ink])
        entity.name = "label.\(string)"
        entity.position = position
        return entity
    }

    private static func color(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    /// The book an entity belongs to. A hit lands on a spine, a page block or a
    /// title, so this walks up until it finds one.
    public func book(for entity: Entity) -> JournalBook? {
        var candidate: Entity? = entity
        while let current = candidate {
            if let match = booksByID.values.first(where: { $0.root === current }) {
                return match.book
            }
            candidate = current.parent
        }
        return nil
    }

    /// Find a book the house named, loosely.
    ///
    /// The cue names a PERFORMANCE, not a journal, so a title has to be
    /// recovered from the reply. It works and it is embarrassing; when
    /// `behavior_cue` grows a subject this is deleted rather than improved.
    public func book(matchingTitle title: String) -> JournalBook? {
        let needle = title.lowercased()
        guard !needle.isEmpty else { return nil }
        return booksByID.values.map(\.book).first {
            let candidate = $0.title.lowercased()
            return candidate == needle
                || candidate.contains(needle)
                || needle.contains(candidate)
        }
    }
}
