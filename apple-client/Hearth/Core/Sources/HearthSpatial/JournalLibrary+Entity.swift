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
    /// How tall the whole library is, in its own units.
    private var contentHeight: Float = 0

    /// The invisible surface a drag can grab.
    ///
    /// Without it the only things in the library with a collision shape are the
    /// book spines, so `targetedToEntity` found nothing in the gaps between
    /// them and a scroll only started if the drag began exactly on a book. A
    /// bookcase you can only scroll by grabbing a book is a bookcase that does
    /// not scroll.
    ///
    /// A child of `root` rather than the scroller, so it stays put while the
    /// shelves move past it, and interactive only -- the persona's prop must
    /// not be grabbable at all.
    /// The invisible slab a pinch lands on.
    ///
    /// Public because a room hosts this differently from a box: in the volume a
    /// drag on it SCROLLS the shelves, and in a room -- where a bookcase stands
    /// on the floor at life size and there is nothing to scroll -- the same
    /// surface is what you grab to move the whole thing somewhere else. One
    /// grabbable surface, two hosts, two meanings.
    public let dragSurface = Entity()

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
        if interactive {
            dragSurface.name = "JournalLibrary.dragSurface"
            root.addChild(dragSurface)
        }
    }

    /// How much of the library the box actually shows, in the library's own
    /// units: from its origin down to the clip floor.
    private var visibleHeight: Float {
        guard let clipBelowInParent else { return contentHeight }
        return max(0, (root.position.y - clipBelowInParent) / max(presentationScale, 0.0001))
    }

    /// Re-measure the travel and the surface a drag can grab.
    ///
    /// Both depend on the same three things -- how tall the content is, where
    /// the library sits, and where the floor is -- so both are recomputed
    /// together whenever any of them moves.
    private func recomputeTravel() {
        maxScroll = max(0, contentHeight - visibleHeight)
        scroll = min(scroll, maxScroll)

        guard interactive else { return }
        let height = max(visibleHeight, JournalBookEntity.height)
        dragSurface.components.set(CollisionComponent(
            shapes: [.generateBox(size: SIMD3<Float>(boardWidth + reachBeyondBoard,
                                                     height,
                                                     JournalBookEntity.depth * 0.5))]))
        dragSurface.components.set(InputTargetComponent())
        // Behind the books, centred on the band the box shows and reaching the
        // same way the shelves do, so a drag anywhere over or beside the
        // library is caught while a pinch still finds the nearer spine first.
        dragSurface.position = SIMD3<Float>(-reachBeyondBoard * 0.5,
                                            -height * 0.5,
                                            -JournalBookEntity.depth * 0.8)
    }

    /// How large the library is presented, with 1 being life size.
    ///
    /// The geometry is authored at life size and never rebuilt; this is the one
    /// dial that changes how big it comes out. A host that wants a bookcase
    /// leaves it alone, and one that wants the persona's investigation prop
    /// turns it down to a tenth.
    ///
    /// Note for anyone converting a gesture into a scroll: this scales the
    /// world the scroller moves in, so a drag measured in real distance has to
    /// be divided by it or the shelves will not track the finger.
    public var presentationScale: Float = 1 {
        didSet {
            root.scale = SIMD3<Float>(repeating: presentationScale)
            recomputeTravel()
            applyClip()
        }
    }

    /// Nothing draws below this height, given in the PARENT's space.
    ///
    /// A clipping plane, built the only way RealityKit offers one: there is no
    /// user clip plane, and a real shader clip would be a whole material for a
    /// straight line. So each shelf is culled against the plane and faded
    /// across a short band as it crosses -- per shelf rather than per pixel,
    /// which is enough because shelves are discrete and a board either belongs
    /// on screen or does not.
    ///
    /// Taken in the parent's space on purpose. The host knows where the
    /// composer and the button shelf are in the VOLUME; it should not also have
    /// to know the library's own position and scale to say "not below here".
    public var clipBelowInParent: Float? {
        didSet { recomputeTravel(); applyClip() }
    }

    /// How far a shelf fades over as it crosses the plane.
    ///
    /// Nearly a book tall, so a shelf arrives over a real distance rather than
    /// switching on. Long enough to read as approaching and short enough that
    /// nothing spends its life half-there.
    private var clipFade: Float { JournalBookEntity.height * 0.8 }

    /// Each child's lowest point, in its own parent's space.
    ///
    /// Measured once at build time and cached, because the cull DISABLES what
    /// it hides -- and a disabled entity reports no visual bounds, so measuring
    /// during the cull would make anything hidden unable to come back.
    ///
    /// It has to be measured rather than assumed. A shelf's bottom is its
    /// board, a room label's is its own baseline, and they sit at different
    /// heights; culling both by one guessed offset is what let a room's caption
    /// appear while its books were still hidden.
    private var bottomOffsets: [ObjectIdentifier: Float] = [:]

    /// How far down the library is scrolled, in metres of its OWN space.
    public var scroll: Float = 0 {
        didSet {
            guard interactive else { return }
            scroller.position.y = min(maxScroll, max(0, scroll))
            applyClip()
        }
    }

    /// Cull every shelf against the plane.
    ///
    /// Opacity AND `isEnabled`: a fully transparent entity still answers a hit
    /// test, so a book faded out under the composer would still open if pinched
    /// through it. Fading alone would make the plane a lie.
    private func applyClip() {
        guard let clipBelowInParent else {
            for child in scroller.children {
                child.isEnabled = true
                child.components.remove(OpacityComponent.self)
            }
            return
        }
        let scale = max(presentationScale, 0.0001)
        // The plane, expressed in the scroller's own units.
        let plane = (clipBelowInParent - root.position.y) / scale - scroller.position.y

        for child in scroller.children {
            let bottom = child.position.y + (bottomOffsets[ObjectIdentifier(child)] ?? 0)
            let t = Self.smoothstep(plane, plane + clipFade, bottom)
            child.isEnabled = t > 0.01
            child.components.set(OpacityComponent(opacity: t))
        }
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - edge0) / max(edge1 - edge0, 1e-4)))
        return t * t * (3 - 2 * t)
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

        // The masthead sits just above the first room's label, NOT a whole
        // shelf higher.
        //
        // It used to take row 0 for itself, which left a full board's pitch of
        // empty air between the title and the first shelf -- a gap that reads
        // as a shelf that failed to load rather than as breathing room. It gets
        // a masthead's worth of clearance and no more.
        // NOTHING SITS ABOVE THE ORIGIN.
        //
        // The masthead used to, and so did every room's first label, while
        // `scroll` is clamped to 0...maxScroll -- downward only. So the top of
        // the library was above the box's ceiling with no way to bring it back:
        // clipped on arrival and unreachable by scrolling. Everything hangs
        // BELOW y = 0 now, and the origin is the top of the content.
        // How far the first shelf hangs below the masthead.
        //
        // It has to clear the masthead block AND the first room's own label,
        // and the second term is the one that was missed: a room's label sits
        // `labelRise` ABOVE its board, so a drop shorter than that puts the
        // first caption above the masthead and the first shelf's books through
        // it. This was 0.34 against a rise of 0.78, so the top shelf was
        // printed straight over the title.
        let mastheadBlock = JournalBookEntity.height * 0.30
        let topDrop = labelRise + mastheadBlock
        scroller.addChild(Self.text("Journal", size: JournalBookEntity.height * 0.115,
                                    at: SIMD3<Float>(-boardWidth * 0.5, 0, 0)))
        scroller.addChild(Self.text("kept by Selene", size: JournalBookEntity.height * 0.062,
                                    at: SIMD3<Float>(-boardWidth * 0.5,
                                                     -JournalBookEntity.height * 0.15, 0),
                                    muted: true))

        for (books, label, caption) in Self.roomOrder(heart: heart, life: life,
                                                      projects: projects, seedlings: seedlings) {
            let labelY = -topDrop - Float(row) * shelfPitch + labelRise
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
                scroller.addChild(board(slice, palette: palette, atRow: row, topDrop: topDrop))
                row += 1
            }
        }

        // The masthead and the room labels take height the boards do not, so
        // the travel has to clear them too or the bottom shelf stops just out
        // of reach.
        // Measure every child's underside now, while they are all enabled.
        bottomOffsets.removeAll()
        for child in scroller.children {
            let bounds = child.visualBounds(relativeTo: scroller)
            bottomOffsets[ObjectIdentifier(child)] = bounds.min.y - child.position.y
        }

        // Travel is the content that does not fit, measured rather than
        // guessed from a row count -- and the library already knows both terms:
        // how tall it is, and how much of it the box shows between its origin
        // and the clip floor.
        contentHeight = topDrop + Float(row) * shelfPitch
        recomputeTravel()
        scroll = 0
        applyClip()
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
                       atRow row: Int,
                       topDrop: Float) -> Entity {
        let shelf = Entity()
        shelf.position = SIMD3<Float>(0, -topDrop - Float(row) * shelfPitch, 0)

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

        // The shelf itself is grabbable, behind its books.
        //
        // The backing surface catches drags over the library as a whole; this
        // catches them on a shelf specifically, which is where a hand naturally
        // goes. Set BEHIND the spines so a pinch still finds the nearer book
        // first -- the two gestures share the same targets and are told apart
        // by whether the drag travelled, so the only thing that matters here is
        // depth order.
        if interactive {
            shelf.components.set(CollisionComponent(
                shapes: [ShapeResource
                    .generateBox(size: SIMD3<Float>(boardWidth + reachBeyondBoard,
                                                    shelfPitch * 0.9,
                                                    JournalBookEntity.depth * 0.5))
                    // Shifted by half the extension, so the whole of it lands
                    // on the persona's side rather than splitting the
                    // difference and hanging off the far edge too.
                    .offsetBy(translation: SIMD3<Float>(-reachBeyondBoard * 0.5,
                                                        0,
                                                        -JournalBookEntity.depth * 0.8))]))
            shelf.components.set(InputTargetComponent())
        }
        return shelf
    }

    /// How far the grab area reaches PAST the carcass, toward the persona.
    ///
    /// The gap between the orb and the shelves is dead space, and it is where a
    /// hand naturally goes to scroll -- nobody reaches into a bookcase to move
    /// it. Extending the reach into that gap costs nothing and catches the
    /// drags that were landing on nothing at all.
    ///
    /// A quarter of the carcass and no more, and the ceiling is not taste: the
    /// orb sits just beyond it, with a collision shape of its own for the pinch
    /// that starts a voice turn. Reach far enough and a drag meant for the
    /// persona scrolls the library instead.
    private var reachBeyondBoard: Float { boardWidth * 0.25 }

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
