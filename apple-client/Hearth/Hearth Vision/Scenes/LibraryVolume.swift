//
//  LibraryVolume.swift
//  Hearth Vision
//
//  The library: a volume of shelves you scroll, and a book you take off them.
//
//  Its own scene rather than a panel in the main volume, and that is the second
//  correction in a row on this. Books loose in the stage cluttered it; the
//  phone's flat JournalView in a panel read as a website about journals; and a
//  RealityView nested inside an ATTACHMENT -- the obvious way to get 3D into a
//  panel -- puts three-dimensional content inside a view that is rendered onto
//  a plane, which is not a thing attachments do. Design section 1 had the right
//  answer from the start and `SceneID.libraryVolume` has been sitting declared
//  since phase 0: the library is a volumetric window of its own.
//
//  THE TWO GESTURES, and why they do not fight. Pinch-and-drag scrolls the
//  shelves; pinch-and-release opens a book. They are the same pinch, told apart
//  by whether it moved -- which is exactly how a list behaves everywhere else,
//  and here it is written out because a RealityView has no ScrollView to
//  inherit it from. `hasScrolled` is the whole of that arbitration: a drag that
//  travelled more than a couple of millimetres was a scroll, and the tap that
//  ends it opens nothing.
//

import SwiftUI
import RealityKit
import HearthCore
import HearthUI
import HearthSpatial

struct LibraryVolume: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var library = JournalLibrary()

    /// The scrolling root. Everything on the shelves hangs off this, so
    /// scrolling is one entity's position rather than a hundred.
    @State private var shelfRoot = Entity()
    @State private var booksByID: [String: JournalBookEntity] = [:]

    /// The journal being read, or nil for the shelves.
    @State private var reading: JournalBook?

    /// How far the shelves have been scrolled, and how far they can go.
    @State private var scrollY: Float = 0
    @State private var scrollAtGestureStart: Float = 0
    @State private var maxScroll: Float = 0
    @State private var hasScrolled = false

    private let booksPerShelf = 5
    /// Metres between shelves. A book is 0.046 tall, so this leaves the gap a
    /// real shelf has above the spines.
    private let shelfPitch: Float = 0.075

    var body: some View {
        RealityView { content, attachments in
            content.add(shelfRoot)
            if let page = attachments.entity(for: Self.readerID) {
                content.add(page)
                page.position = SIMD3<Float>(0, 0, 0.12)
            }
        } update: { _, attachments in
            attachments.entity(for: Self.readerID)?.isEnabled = reading != nil
            shelfRoot.isEnabled = reading == nil
            shelfRoot.position.y = scrollY
        } attachments: {
            Attachment(id: Self.readerID) {
                if let reading {
                    reader(reading)
                }
            }
        }
        // Drag to scroll. Clamped so the shelves cannot be flung out of the box
        // and lost -- there is no scroll bar in a volume to show you where you
        // went.
        .gesture(
            DragGesture()
                .targetedToEntity(shelfRoot)
                .onChanged { value in
                    if !hasScrolled {
                        scrollAtGestureStart = scrollY
                        hasScrolled = false
                    }
                    let dy = Float(value.translation.height) * -0.0009
                    if abs(value.translation.height) > 6 { hasScrolled = true }
                    scrollY = min(maxScroll, max(0, scrollAtGestureStart + dy))
                }
                .onEnded { _ in
                    scrollAtGestureStart = scrollY
                    // Cleared on the NEXT tap rather than here: the tap gesture
                    // fires after this, and it has to know whether this drag
                    // was a scroll.
                }
        )
        // Pinch a book to read it.
        .gesture(
            SpatialTapGesture()
                .targetedToEntity(shelfRoot)
                .onEnded { value in
                    defer { hasScrolled = false }
                    guard !hasScrolled else { return }
                    guard let hit = book(for: value.entity) else { return }
                    reading = hit.book
                }
        )
        .task {
            await library.load()
            rebuild()
            openIfNamed(in: viewModel.liveTranscript)
        }
        .onChange(of: library.allBooks.map(\.id)) { _, _ in rebuild() }
        .onChange(of: viewModel.personaPalette) { _, palette in
            for entity in booksByID.values { entity.apply(palette: palette) }
        }
        // Design section 5's second open path. The library watches the reply
        // itself rather than being handed a title by whoever opened it: the
        // scenes are siblings, and threading state between two windows to say
        // one string would be a wire nobody could follow.
        .onChange(of: viewModel.liveTranscript) { _, text in
            openIfNamed(in: text)
        }
    }

    // MARK: - Building the shelves

    private func rebuild() {
        for child in shelfRoot.children.map({ $0 }) { child.removeFromParent() }
        booksByID.removeAll()

        let all = library.allBooks
        let rows = stride(from: 0, to: all.count, by: booksPerShelf).map {
            Array(all[$0..<min($0 + booksPerShelf, all.count)])
        }

        for (rowIndex, row) in rows.enumerated() {
            let shelf = Entity()
            shelf.position = SIMD3<Float>(0, -Float(rowIndex) * shelfPitch, 0)

            let span = Float(row.count) * JournalBookEntity.width * 1.5
            shelf.addChild(JournalShelfPlank.make(
                width: max(span, JournalBookEntity.width * 3)))

            for (index, book) in row.enumerated() {
                let entity = JournalBookEntity(book: book, palette: viewModel.personaPalette)
                // Spread from the centre, so a short last shelf stays centred
                // under the ones above it.
                let offset = Float(index) - Float(row.count - 1) / 2
                entity.root.position = SIMD3<Float>(offset * JournalBookEntity.width * 1.5, 0, 0)
                // A slight alternating lean: a shelf of perfectly upright books
                // looks printed rather than kept.
                entity.root.orientation = simd_quatf(
                    angle: (index % 3 == 1) ? 0.07 : 0,
                    axis: SIMD3<Float>(0, 0, 1))
                shelf.addChild(entity.root)
                booksByID[book.id] = entity
            }
            shelfRoot.addChild(shelf)
        }

        // Start with the top shelf at eye level and let the rest hang below.
        let visibleRows: Float = 3
        maxScroll = max(0, (Float(rows.count) - visibleRows) * shelfPitch)
        scrollY = 0
        shelfRoot.position = SIMD3<Float>(0, 0, 0)
    }

    /// The book an entity belongs to. The hit lands on a cover or a page block,
    /// so this walks up until it finds one.
    private func book(for entity: Entity) -> JournalBookEntity? {
        var candidate: Entity? = entity
        while let current = candidate {
            if let match = booksByID.values.first(where: { $0.root === current }) { return match }
            candidate = current.parent
        }
        return nil
    }

    /// Open whichever journal the house just named, if it named one.
    ///
    /// Crude, and the doc says so where it matters: the cue names a
    /// PERFORMANCE, not a journal, so the title is scraped out of the reply and
    /// matched loosely. It works and it is embarrassing. The harness knows
    /// which journal it read, so `behavior_cue` should grow a `subject` and
    /// this whole function should be deleted rather than improved.
    private func openIfNamed(in text: String) {
        guard reading == nil, !text.isEmpty else { return }
        let title = Self.firstQuotedTitle(in: text)
        guard !title.isEmpty else { return }
        let needle = title.lowercased()
        reading = library.allBooks.first {
            let candidate = $0.title.lowercased()
            return candidate == needle
                || candidate.contains(needle)
                || needle.contains(candidate)
        }
    }

    /// The first quoted run in the house's reply.
    private static func firstQuotedTitle(in text: String) -> String {
        for quote in ["\u{201C}", "\"", "'"] {
            let parts = text.components(separatedBy: quote)
            if parts.count >= 2, !parts[1].isEmpty, parts[1].count < 60 {
                return parts[1]
            }
        }
        return ""
    }

    // MARK: - Reading

    /// The proven iOS reading view, unchanged. The library is new; what is
    /// written in a journal is not.
    private func reader(_ book: JournalBook) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    reading = nil
                } label: {
                    Label("Shelves", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .tint(HearthPalette.ember)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(HearthPalette.parchment)

            JournalBookView(book: book)
        }
        .frame(width: 460, height: 620)
        .background(HearthPalette.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private static let readerID = "hearth.library-reader"
}
