//
//  CardOrbitLayout.swift
//  HearthSpatial
//
//  Where the cards float. Positions are in the host's local metre space, with
//  the origin at the volume centre, +y up and +z toward the viewer.
//
//  This decides placement and nothing else. What a card IS, when it appears and
//  when it expires belong to CardStore and the shared card library; a layout
//  that also owned lifecycle would be a second answer to a question already
//  settled on the phone.
//
//  Ported from Valinor, device-validated 2026-06-12. The numbers are unchanged
//  because they were tuned against a real headset and nothing here has a better
//  claim than that. The `#if os(visionOS)` guard around the original is gone:
//  this is arithmetic on three floats, it compiles anywhere, and the guard only
//  ever existed because the file lived in a shared iOS target.
//

import simd

public enum CardOrbitLayout {
    /// Horizontal offset to the orb's LEFT, in metres.
    public static let leftX: Float = -0.28

    /// Vertical spacing between stacked cards, in metres.
    public static let verticalSpacing: Float = 0.22

    /// The orb rides LOW in the volume, near the window handle, so the whole
    /// thing can be set down on a real table -- and so there is room above it
    /// for long-form cards. Orb and cards share this height.
    public static let orbY: Float = -0.22

    /// Absolute position for the card at `index` of `count`.
    ///
    /// Cards stack in a column to the orb's left at the orb's height, so they
    /// never occlude the bead or the live text above it.
    public static func position(index: Int, count: Int) -> SIMD3<Float> {
        SIMD3<Float>(leftX, orbY + columnOffset(index: index, count: count), 0)
    }

    /// Offset RELATIVE TO THE ORB, for when card entities are parented to the
    /// rig rather than placed absolutely.
    ///
    /// This is what phase 3 uses: design section 6 anchors cards to the rig so
    /// a travelling orb carries its work with it. In the volume the two forms
    /// differ only by `orbY`.
    public static func offsetFromOrb(index: Int, count: Int) -> SIMD3<Float> {
        SIMD3<Float>(leftX, columnOffset(index: index, count: count), 0)
    }

    /// The column arithmetic both forms share. Centred on the stack, so adding
    /// a card grows the column in both directions rather than pushing the whole
    /// thing down.
    private static func columnOffset(index: Int, count: Int) -> Float {
        let n = max(1, count)
        let topY = Float(n - 1) * verticalSpacing * 0.5
        return topY - Float(index) * verticalSpacing
    }
}
