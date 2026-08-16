//
//  FaceFeed.swift
//  Hearth
//
//  The side channel into the face's render loop.
//
//  Two of the three things the face needs arrive at rates that must not become
//  view updates. Amplitude lands every audio buffer, and republishing it a
//  second time (ChatViewModel already publishes `ttsAmplitude` for the orb)
//  would push the whole stage through SwiftUI's diff at audio rate for a
//  drawing that redraws itself sixty times a second anyway. So these are plain
//  vars, written by the view model and read inside the Canvas draw -- never
//  @Published, deliberately.
//
//  A singleton because the app has exactly one stage, and threading a
//  reference from ChatViewModel through HearthMainView into the view would buy
//  nothing but a longer signature. @MainActor because both ends are already
//  there: the WS callbacks hop to the main actor, and a render loop is a view.
//

import Foundation

@MainActor
public final class FaceFeed {
    public static let shared = FaceFeed()

    /// Smoothed TTS playback amplitude, 0..1. The mouth's whole story.
    public var speechLevel: Double = 0

    /// The last expression the harness named, with the time it fired. Stale
    /// cues are inert -- the director's envelope has long since decayed -- so
    /// this is only ever replaced, never cleared on a timer.
    public var cue: FaceCue?

    /// The composer is up. Not "the field has focus": focus is lost the moment
    /// a keyboard dismisses or a menu opens, and the face should keep watching
    /// the place the words are being typed.
    public var composerUp: Bool = false

    private init() {}
}
