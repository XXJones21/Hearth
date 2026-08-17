//
//  BehaviorFeed.swift
//  Hearth
//
//  The side channel into the choreography, and a deliberate sibling of
//  FaceFeed: same shape, same reasons, same actor.
//
//  The harness names the performance and the client stages it. That is the seam
//  `tts_chunk_start` already uses to name a face expression, and this is the
//  same seam one level up -- the house says "I am consulting a journal", and
//  what that LOOKS like is entirely the client's business. A server that had to
//  know the orb flies to a shelf would be a server that breaks when the shelf
//  moves.
//
//  Plain vars rather than @Published, for FaceFeed's reason: a cue is read
//  inside a render loop that already runs sixty times a second, and publishing
//  it would push the whole stage through SwiftUI's diff to tell it something it
//  is about to look at anyway.
//

import Foundation

/// One named performance, and which edge of it this is.
public struct BehaviorCue: Sendable, Equatable {
    public enum Phase: String, Sendable, Equatable {
        case start
        case end
    }

    /// The harness's name for the performance. Deliberately a `String` and not
    /// an enum: the vocabulary is OPEN. A house that learns a new tool starts
    /// naming it immediately, and a client that had to ship an enum case first
    /// would show nothing until it was rebuilt. An unknown name resolves to the
    /// generic working behaviour, which is a worse answer than the right one
    /// and a much better answer than none.
    public let name: String

    public let phase: Phase

    /// When it fired, in milliseconds on the same clock the director ticks.
    public let at: Double

    public init(name: String, phase: Phase, at: Double) {
        self.name = name
        self.phase = phase
        self.at = at
    }
}

@MainActor
public final class BehaviorFeed {
    public static let shared = BehaviorFeed()

    /// The last cue the house named. Replaced, never cleared on a timer: the
    /// director decides when a performance is over, and an `end` cue is itself
    /// a cue rather than the absence of one.
    public var cue: BehaviorCue?

    /// Monotonically bumped whenever `cue` is written, so a reader can tell a
    /// NEW cue from the same one still sitting there.
    ///
    /// Without this, two identical cues in a row -- a second
    /// `consulting_journal` for a second journal, which is an ordinary thing to
    /// happen -- would be indistinguishable from one cue read twice, and the
    /// second performance would never start.
    public private(set) var revision: UInt64 = 0

    /// Post a cue. The one way in, so `revision` cannot be forgotten.
    public func post(_ cue: BehaviorCue) {
        self.cue = cue
        revision &+= 1
    }

    private init() {}
}
