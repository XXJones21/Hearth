//
//  LibraryPanel.swift
//  Hearth Vision
//
//  The library: shelves of real books, that you scroll.
//
//  This is the correction to two earlier attempts, and the answer turned out to
//  be both of them together. The first put book ENTITIES loose in the volume,
//  where they floated with nothing to stand on and cluttered a stage that is
//  meant to hold a persona. The second put the phone's flat JournalView in a
//  panel, which reads as a website about journals rather than a library. What
//  works is a SwiftUI window whose CONTENTS are RealityKit entities: shelves and
//  books in three dimensions, laid out by SwiftUI so scrolling and selection
//  come from the system rather than from geometry nobody wants to write.
//
//  WHY THE LAYOUT IS SWIFTUI'S. Pinch-and-scroll through the library and pinch
//  to open one are the two gestures that matter, and they conflict: a drag on an
//  entity is how you scroll AND how you would grab a book. Inside a ScrollView
//  the system already knows the difference -- it has arbitrated scroll against
//  tap on every Apple platform for fifteen years -- so each book is a Button
//  whose label happens to be three-dimensional, and neither gesture has to be
//  invented.
//
//  ONE RealityView PER SHELF, not per book: the plank and the books that stand
//  on it are one picture, and a row is the smallest thing that is still a shelf.
//

import SwiftUI
import RealityKit
import HearthCore
import HearthUI
import HearthSpatial

struct LibraryPanel: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var library = JournalLibrary()

    /// The journal being read, or nil for the shelves.
    ///
    /// Reading REPLACES the shelves rather than floating over them. A library
    /// you can still see behind the page you are reading is a library competing
    /// with it, and the way back is one control.
    @State private var reading: JournalBook?

    /// A title the house named, to be opened once the library has loaded.
    ///
    /// The second of design section 5's open paths arrives before the shelves
    /// do: the orb flies over and the cue lands while `load()` is still in
    /// flight, so the request is parked here and honoured on arrival.
    let pendingTitle: String?

    private let booksPerShelf = 5

    var body: some View {
        Group {
            if let reading {
                reader(reading)
            } else {
                shelves
            }
        }
        .task {
            await library.load()
            openPendingIfPossible()
        }
        .onChange(of: pendingTitle) { _, _ in openPendingIfPossible() }
    }

    // MARK: - The shelves

    private var shelves: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if library.isEmpty && !library.isLoading {
                    empty
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    ShelfRowView(
                        books: row,
                        palette: viewModel.personaPalette,
                        onSelect: { reading = $0 })
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.visible)
    }

    /// Books in shelf order, cut into rows.
    ///
    /// `allBooks` keeps heart, life, projects and seedlings in that order, so a
    /// row rarely straddles two kinds and the colour groupings read as groups
    /// without a heading between them.
    private var rows: [[JournalBook]] {
        stride(from: 0, to: library.allBooks.count, by: booksPerShelf).map {
            Array(library.allBooks[$0..<min($0 + booksPerShelf, library.allBooks.count)])
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("The shelves are bare")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
            Text("Journals appear here as the house writes them.")
                .font(.system(size: 12.5))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Reading

    /// The proven iOS reading view, unchanged. The library is new; what is
    /// written in a journal is not, and a second reader would be a second thing
    /// to keep in step.
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

            JournalBookView(book: book)
        }
    }

    private func openPendingIfPossible() {
        guard reading == nil, let pendingTitle, !pendingTitle.isEmpty else { return }
        let needle = pendingTitle.lowercased()
        reading = library.allBooks.first {
            let candidate = $0.title.lowercased()
            return candidate == needle
                || candidate.contains(needle)
                || needle.contains(candidate)
        }
    }
}

// MARK: - One shelf

/// A plank and the books standing on it.
///
/// The RealityView draws; the overlaid buttons take the taps. Hit-testing
/// entities inside a scrolling container is the fight this avoids: SwiftUI
/// already knows a tap from a scroll, and the books are on a known grid, so the
/// buttons can simply sit where the books are.
private struct ShelfRowView: View {
    let books: [JournalBook]
    let palette: PersonaPalette
    let onSelect: (JournalBook) -> Void

    /// Points per shelf. Enough for a book to read as an object rather than an
    /// icon, and short enough that several shelves are on screen at once --
    /// which is what makes it a library rather than a list.
    private let rowHeight: CGFloat = 132

    var body: some View {
        RealityView { content in
            let row = Entity()
            let span = Float(books.count) * JournalBookEntity.width * 1.5
            row.addChild(JournalShelfPlank.make(width: max(span, JournalBookEntity.width * 3)))

            for (index, book) in books.enumerated() {
                let entity = JournalBookEntity(book: book, palette: palette)
                // Spread from the centre, so a short last shelf stays centred
                // under the ones above it.
                let offset = (Float(index) - Float(books.count - 1) / 2)
                entity.root.position = SIMD3<Float>(offset * JournalBookEntity.width * 1.5, 0, 0)
                // A little lean, alternating, because a shelf of perfectly
                // upright books looks printed rather than kept.
                entity.root.orientation = simd_quatf(
                    angle: (index % 3 == 1) ? 0.07 : 0,
                    axis: SIMD3<Float>(0, 0, 1))
                row.addChild(entity.root)
            }
            content.add(row)
        }
        .frame(height: rowHeight)
        .overlay {
            // The taps. One button per book, laid on the same grid the entities
            // use, so the two cannot drift apart.
            HStack(spacing: 0) {
                ForEach(books) { book in
                    Button {
                        onSelect(book)
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(book.title)
                    .accessibilityHint("Opens this journal")
                }
            }
            .frame(maxWidth: CGFloat(books.count) * 62)
        }
    }
}
