//
//  JournalShelf.swift
//  HearthSpatial
//
//  The library, as a shelf of books.
//
//  Laid out from the same server-fed `JournalModels` the phone renders, which
//  is the point: this is not a second library, it is the same library with a
//  different renderer. A journal appearing in the house appears here, and
//  nothing has to be told twice.
//
//  Design section 5 calls the shelf "the dynamic-growth point", and `apply`
//  below is that: it diffs against what is already standing so a rebuild does
//  not blow away a book the reader has open in their hands.
//
//  ONE SHELF, THREE SIZES. Compact in the main volume, full size in the library
//  volume, settled near a real surface in the immersive house -- the same
//  entities in all three, scaled by their host. That is what `scale` is for,
//  and it is why nothing here knows which scene it is in.
//

import Foundation
import RealityKit
import simd
import HearthCore

@MainActor
public final class JournalShelf {
    /// What a host adds to its scene.
    public let root: Entity

    private var books: [String: JournalBookEntity] = [:]
    private var order: [String] = []
    private var palette: PersonaPalette = .fallback

    /// The book currently open, if any. At most one: a shelf of open books is
    /// a mess, and closing the last one on opening the next is what a person
    /// does with real books anyway.
    public private(set) var openBookID: String?

    /// Books per row before wrapping. The compact shelf in the main volume gets
    /// fewer, so it stays a hint of a library rather than the thing itself.
    public var columns: Int = 6

    private let spacing: Float = 0.019
    private let rowHeight: Float = 0.088

    public init() {
        root = Entity()
        root.name = "JournalShelf"
    }

    /// Rebuild from the house's library.
    ///
    /// Diffed rather than cleared. A `journal_update` arriving while someone is
    /// reading must not tear the book out of their hands, and rebuilding from
    /// scratch would also restart every hinge animation on screen.
    public func apply(books incoming: [JournalBook], palette: PersonaPalette) {
        self.palette = palette

        let incomingIDs = Set(incoming.map(\.id))

        // Gone from the house: take them off the shelf.
        for id in order where !incomingIDs.contains(id) {
            books[id]?.root.removeFromParent()
            books.removeValue(forKey: id)
            if openBookID == id { openBookID = nil }
        }
        order = incoming.map(\.id)

        for book in incoming {
            if let existing = books[book.id] {
                existing.apply(palette: palette)
            } else {
                let entity = JournalBookEntity(book: book, palette: palette)
                books[book.id] = entity
                root.addChild(entity.root)
            }
        }

        layout()
    }

    /// Place every book. Rows fill left to right, growing downward.
    private func layout() {
        let n = max(1, columns)
        for (index, id) in order.enumerated() {
            guard let entity = books[id] else { continue }
            let row = index / n
            let column = index % n
            let inRow = min(n, order.count - row * n)
            // Centre each row on its own count, so a short last row does not
            // hang off to one side.
            let rowWidth = Float(inRow - 1) * spacing
            entity.root.position = SIMD3<Float>(
                Float(column) * spacing - rowWidth * 0.5,
                -Float(row) * rowHeight,
                0)
        }
    }

    /// The book for an entity the host's gesture hit, if it is one of ours.
    ///
    /// The hit lands on a child -- a cover, a page block -- so this walks up
    /// until it finds a book or runs out of parents.
    public func book(for entity: Entity) -> JournalBookEntity? {
        var candidate: Entity? = entity
        while let current = candidate {
            if let match = books.values.first(where: { $0.root === current }) { return match }
            candidate = current.parent
        }
        return nil
    }

    /// Open one book and close whatever was open.
    public func open(_ id: String) {
        if let openBookID, openBookID != id { books[openBookID]?.setOpen(false) }
        books[id]?.setOpen(true)
        openBookID = id
    }

    public func closeOpenBook() {
        guard let openBookID else { return }
        books[openBookID]?.setOpen(false)
        self.openBookID = nil
    }

    /// The open book's entity, for the host to hang page attachments on.
    public var openBook: JournalBookEntity? {
        openBookID.flatMap { books[$0] }
    }

    /// Find a book by title, loosely.
    ///
    /// This is how the `consulting_journal` choreography finds what the house
    /// just read: the cue names a performance, not an id, and the house's own
    /// answer mentions the journal by title. Case- and substring-tolerant
    /// because a title in prose is rarely the title verbatim.
    public func book(matchingTitle title: String) -> JournalBookEntity? {
        let needle = title.lowercased()
        guard !needle.isEmpty else { return nil }
        return order.compactMap { books[$0] }.first {
            let candidate = $0.book.title.lowercased()
            return candidate == needle
                || candidate.contains(needle)
                || needle.contains(candidate)
        }
    }

    /// Where the shelf's centre is in world space, for the director to aim at.
    public var worldCenter: SIMD3<Float> { root.position(relativeTo: nil) }
}
