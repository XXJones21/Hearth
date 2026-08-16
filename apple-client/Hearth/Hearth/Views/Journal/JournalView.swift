//
//  JournalView.swift
//  Hearth
//
//  Selene's Library on a phone. The desktop shelf translated to portrait:
//  shelves become horizontally scrolling rails (a spine is tall and narrow,
//  which is exactly what a portrait phone scrolls sideways without apology),
//  and the two-page spread becomes two pushes -- her keeper page leads, the
//  entries follow, and an entry is one deliberate tap deeper.
//
//  Rooms are in Selene's locked order (tasks/journal-design.md): the Heart on
//  display, then the Curator's Alcove, the Active Forge, the Glass
//  Conservatory, and the Sanctum as a door not yet open.
//
//  Mockup of record: hearth-pitch/mockups/hearth-ios-journal-mockup.html
//

import SwiftUI
import HearthCore

struct JournalView: View {
    @StateObject private var library = JournalLibrary()
    @Environment(\.dismiss) private var dismiss
    /// Desktop's "Search the library" box: filters shelf titles. Empty query
    /// shows the rooms as they stand.
    @State private var query = ""

    /// Case-insensitive title filter, desktop's rule.
    private func matching(_ books: [JournalBook]) -> [JournalBook] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return books }
        return books.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead

                    if library.isLoading && library.isEmpty {
                        loading
                    } else if let error = library.loadError, library.isEmpty {
                        failure(error)
                    } else {
                        let heart = matching(library.heart)
                        let life = matching(library.life)
                        let projects = matching(library.projects)
                        let seedlings = matching(library.seedlings)

                        if !heart.isEmpty {
                            Room(label: "The Heart of the Library",
                                 caption: "on display, the volumes that live and grow") {
                                heartDisplay(heart)
                            }
                        }
                        if !life.isEmpty {
                            Room(label: "The Curator's Alcove",
                                 caption: "the person before the works") {
                                shelf(life)
                            }
                        }
                        if !projects.isEmpty {
                            Room(label: "The Active Forge",
                                 caption: "works in motion") {
                                shelf(projects)
                            }
                        }
                        if !seedlings.isEmpty {
                            Room(label: "The Glass Conservatory",
                                 caption: "seedlings, one page each") {
                                conservatory(seedlings)
                            }
                        }
                        if heart.isEmpty && life.isEmpty && projects.isEmpty && seedlings.isEmpty {
                            Text("No book answers to \"\(query)\".")
                                .font(.system(size: 12.5))
                                .foregroundStyle(HearthPalette.fawn)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                        sanctum
                    }
                }
                .padding(.bottom, 28)
            }
            .background(HearthPalette.cream.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Search the library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hearth") { dismiss() }
                        .tint(HearthPalette.ember)
                }
            }
            .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await library.load() }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Journal")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text("kept by Selene")
                .font(.system(size: 12.5))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(HearthPalette.fennec)
            Text("Opening the library...")
                .font(.system(size: 13))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text("The library is closed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
            Text(message)
                .font(.system(size: 12.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(HearthPalette.fawn)
            Button("Try again") { Task { await library.load() } }
                .font(.system(size: 13, weight: .semibold))
                .tint(HearthPalette.ember)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 50)
    }

    // MARK: - Rooms

    /// The living volumes stand face-out, the way a bookshop turns its featured
    /// titles to camera. Three fit across a phone without scrolling.
    private func heartDisplay(_ books: [JournalBook]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(books) { book in
                    NavigationLink { JournalBookView(book: book) } label: {
                        HeroBookCover(book: book)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(book.title), \(book.pages) pages")
                }
            }
            .padding(.horizontal, 18)

            ShelfBoard(height: 8)
            // The board's warm spill, which is what makes them read as lit.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [HearthPalette.honey.opacity(0.30), .clear],
                        center: .center, startRadius: 0, endRadius: 90
                    )
                )
                .frame(height: 16)
                .padding(.horizontal, 22)
        }
    }

    private func shelf(_ books: [JournalBook]) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(books) { book in
                        NavigationLink { JournalBookView(book: book) } label: {
                            BookSpine(book: book, height: 132)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(book.title), \(book.pages) pages")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
            }
            ShelfBoard(height: 7)
        }
    }

    private func conservatory(_ books: [JournalBook]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(books) { book in
                    NavigationLink { JournalBookView(book: book) } label: {
                        BookSpine(book: book, height: 96)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(book.title), \(book.pages) pages")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        // Glass, via tokens: a literal white panel glares in ember mode.
        .background(
            LinearGradient(
                colors: [HearthPalette.fluff.opacity(0.62), HearthPalette.parchment.opacity(0.4)],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HearthPalette.linen, lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    private var sanctum: some View {
        VStack(spacing: 3) {
            Text("The Sanctum of Reflection")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(HearthPalette.roast)
            Text("where memory is composed, not stored")
                .font(.system(size: 11))
                .foregroundStyle(HearthPalette.fawn)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(HearthPalette.glowtint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HearthPalette.bubbleLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }
}

// MARK: - Room chrome

private struct Room<Content: View>: View {
    let label: String
    let caption: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(HearthPalette.ember)
                .padding(.horizontal, 18)
            Text(caption)
                .font(.system(size: 11.5))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .padding(.bottom, 9)
            content
        }
        .padding(.top, 16)
    }
}

private struct ShelfBoard: View {
    let height: CGFloat

    var body: some View {
        // Palette tokens, not literals: the boards were the one furniture
        // that stayed daylight-brown in ember mode.
        LinearGradient(
            colors: [HearthPalette.journalWoodHi, HearthPalette.journalWoodLo],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: height)
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(bottomLeading: 5, bottomTrailing: 5), style: .continuous
        ))
        .shadow(color: HearthPalette.shadow, radius: 4, y: 3)
        .padding(.horizontal, 14)
    }
}

// MARK: - Books

/// Face-out cover for a living volume: spine sliver at the left, page block
/// along the fore-edge, embossed frame, and the glow that marks it as living.
struct HeroBookCover: View {
    let book: JournalBook

    private var cover: LinearGradient {
        let pairs: [(Color, Color)] = [
            (Color(red: 0.725, green: 0.443, blue: 0.290), Color(red: 0.557, green: 0.357, blue: 0.235)),
            (Color(red: 0.788, green: 0.541, blue: 0.333), Color(red: 0.659, green: 0.384, blue: 0.243)),
            (Color(red: 0.816, green: 0.627, blue: 0.349), Color(red: 0.690, green: 0.486, blue: 0.243))
        ]
        let pair = pairs[book.title.paletteIndex(pairs.count)]
        return LinearGradient(colors: [pair.0, pair.1],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0).frame(height: geo.size.height * 0.33)
                Text(book.title)
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(Color(red: 1, green: 0.953, blue: 0.894))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(red: 1, green: 0.953, blue: 0.894).opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.top, 13)
                Spacer(minLength: 0)
                Text("\(book.pages)")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(Color(red: 1, green: 0.953, blue: 0.894).opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.bottom, 9)
        }
        .frame(height: 126)
        .background(cover)
        .overlay(alignment: .leading) {
            // Spine sliver: a face-out book still shows its hinge.
            LinearGradient(colors: [.black.opacity(0.34), .white.opacity(0.09)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 7)
        }
        .overlay(alignment: .trailing) {
            PageBlock().frame(width: 4).padding(.vertical, 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(red: 1, green: 0.953, blue: 0.894).opacity(0.34), lineWidth: 1)
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 8))
        )
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 2, bottomLeading: 2, bottomTrailing: 7, topTrailing: 7),
            style: .continuous
        ))
        .shadow(color: .black.opacity(0.30), radius: 8, y: 7)
        .shadow(color: HearthPalette.honey.opacity(0.34), radius: 11)
    }

    private var subtitle: String {
        switch book.title {
        case "The Journal":     return "daily sessions"
        case "About Joshua":    return "operator facts"
        case "Selene's Ledger": return "nightly reviews"
        default:                return "living volume"
        }
    }
}

/// Spine-on book. Width carries thickness, so a 13-page project reads as
/// heavier than a seedling without any label saying so.
struct BookSpine: View {
    let book: JournalBook
    let height: CGFloat

    private var width: CGFloat {
        min(46, max(19, 17 + CGFloat(book.pages) * 2.2))
    }

    private static let leathers: [Color] = [
        Color(red: 0.725, green: 0.443, blue: 0.290),
        Color(red: 0.659, green: 0.384, blue: 0.243),
        Color(red: 0.788, green: 0.541, blue: 0.333),
        Color(red: 0.557, green: 0.357, blue: 0.235),
        Color(red: 0.816, green: 0.592, blue: 0.388),
        Color(red: 0.612, green: 0.416, blue: 0.271)
    ]

    var body: some View {
        ZStack {
            background
            // rotationEffect rotates DRAWING, not layout: the text keeps
            // reporting its unrotated width (a long title is ~120pt), which
            // leaks out of the spine in both directions. Constrain the text to
            // the spine's length before rotating, then clip and pin the hit
            // area to the spine rect below -- otherwise neighbouring spines
            // overlap and the wrong book opens.
            Text(book.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.953, blue: 0.894))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: height - 20)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: width, height: height)
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 5, topTrailing: 5),
            style: .continuous
        ))
        .overlay(alignment: .leading) {
            Color.white.opacity(0.16).frame(width: 3)
        }
        // Hit testing is the spine and nothing but the spine.
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.26), radius: 3, x: 1, y: 2)
    }

    /// An empty book is not a bug -- the Archive at the shelf's end is a quiet
    /// promise, so it reads as unbound pages rather than tooled leather.
    @ViewBuilder
    private var background: some View {
        if book.pages == 0 {
            PageBlock()
        } else {
            LinearGradient(
                colors: [Self.leathers[book.title.paletteIndex(Self.leathers.count)],
                         .black.opacity(0.22)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

/// Striated paper edge, used for the fore-edge of a hero book and for the
/// empty Archive spine.
///
/// One gradient, not a stack of stripe views. The ForEach version built ~30
/// subviews per book, which is 600+ views across a shelf and is felt as
/// stutter while scrolling.
struct PageBlock: View {
    // Dynamic palette tokens: pages dim with the room in ember mode. The
    // book LEATHERS above stay literal on purpose -- a bound book keeps its
    // colour in a dim room; the furniture and paper are surface.
    private static let paper = HearthPalette.journalPaper
    private static let shade = HearthPalette.journalPaperLine

    var body: some View {
        Canvas(opaque: true) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.paper))
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 2)),
                    with: .color(Self.shade)
                )
                y += 4
            }
        }
        .background(Self.paper)
    }
}


// MARK: - Stable binding colour

private extension String {
    /// Swift's `hashValue` is seeded per process, so a book changed colour on
    /// every launch. This is deterministic: the same title always gets the same
    /// leather.
    func paletteIndex(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = utf8.reduce(0) { ($0 &+ Int($1)) % 4096 }
        return sum % count
    }
}
