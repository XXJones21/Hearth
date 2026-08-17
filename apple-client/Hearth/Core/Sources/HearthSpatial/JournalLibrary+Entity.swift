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

@MainActor
public final class JournalLibraryEntity {
    /// What a host adds to its scene.
    public let root = Entity()

    /// The part that moves when scrolled. Separate from `root` so the host can
    /// place the library without fighting the scroll offset.
    private let scroller = Entity()

    private var booksByID: [String: JournalBookEntity] = [:]

    /// Metres between one board and the next.
    private let shelfPitch: Float = JournalBookEntity.height * 1.75
    /// Metres of gap between neighbouring spines. The phone uses 9pt against a
    /// 132pt spine; this is that ratio.
    private let spineGap: Float = JournalBookEntity.height * 0.068
    /// How many boards are visible before the rest have to be scrolled to.
    private let visibleRows: Float = 3

    /// How far the shelves can travel. Zero when everything already fits.
    public private(set) var maxScroll: Float = 0

    public init() {
        root.name = "JournalLibrary"
        root.addChild(scroller)
    }

    /// How far down the library is scrolled, in metres. Clamped.
    public var scroll: Float = 0 {
        didSet { scroller.position.y = min(maxScroll, max(0, scroll)) }
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

        let rooms: [[JournalBook]] = [heart, life, projects, seedlings].filter { !$0.isEmpty }
        var row = 0
        for room in rooms {
            // A room longer than a board wraps onto the next one rather than
            // running off the side: there is no horizontal scroll here, because
            // a volume scrolls one way and asking it to do both is how a person
            // loses a shelf.
            for chunk in stride(from: 0, to: room.count, by: booksPerBoard) {
                let slice = Array(room[chunk..<min(chunk + booksPerBoard, room.count)])
                scroller.addChild(board(slice, palette: palette, atRow: row))
                row += 1
            }
        }

        maxScroll = max(0, (Float(row) - visibleRows) * shelfPitch)
        scroll = 0
    }

    private let booksPerBoard = 8

    private func board(_ books: [JournalBook],
                       palette: PersonaPalette,
                       atRow row: Int) -> Entity {
        let shelf = Entity()
        shelf.position = SIMD3<Float>(0, -Float(row) * shelfPitch, 0)

        // Lay the spines out left to right, each taking its own thickness.
        // Books are not evenly spaced, because books are not evenly thick --
        // which is most of what makes a shelf look like a shelf.
        let entities = books.map { JournalBookEntity(book: $0, palette: palette) }
        let total = entities.reduce(Float(0)) { $0 + $1.thickness + spineGap } - spineGap
        var x = -total * 0.5

        for entity in entities {
            x += entity.thickness * 0.5
            entity.root.position = SIMD3<Float>(x, 0, 0)
            x += entity.thickness * 0.5 + spineGap
            shelf.addChild(entity.root)
            booksByID[entity.book.id] = entity
        }

        shelf.addChild(JournalShelfPlank.make(
            width: max(total * 1.08, JournalBookEntity.height * 0.6)))
        return shelf
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
