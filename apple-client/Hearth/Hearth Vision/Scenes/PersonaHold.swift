//
//  PersonaHold.swift
//  Hearth Vision
//
//  One pinch on the persona, two meanings, told apart by how long it lasts.
//
//  A plain pinch starts a voice turn. A pinch HELD for two seconds crosses
//  between the volume and the immersive house, in whichever direction you are
//  currently facing. Design section 1 asks for exactly this, and it is the
//  gesture Valinor's `SulivanVolumeView` already carried and had nowhere to
//  send.
//
//  WHY ONE GESTURE AND NOT TWO. A `TapGesture` and a `LongPressGesture` on the
//  same entity race: SwiftUI has to decide which one owns the pinch, and the
//  answer depends on ordering and on whether either has already failed. The
//  arbitration is ours to make rather than to hope for, and it is the same
//  arbitration the journal library needed between scrolling and opening a book
//  -- which took two attempts there. So this is a single `DragGesture` with a
//  zero minimum distance, which fires on press and on release and lets the
//  elapsed time decide.
//
//  Valinor arrived at the same shape for the same reason, and its third meaning
//  is here now: drag past a threshold and the pinch becomes a reposition, which
//  is how you move the persona somewhere else in a room. It fits the same
//  arbitration because all three are decided from the SAME press -- time for the
//  hold, distance for the drag, neither for the tap.
//

import SwiftUI
import RealityKit
import HearthSpatial

extension View {
    /// - Parameters:
    ///   - onTap: a plain pinch. Nil disables it.
    ///   - onHold: the two-second hold completing.
    ///   - progress: the ramp, 0 to 1, while the hold builds. The rig drives its
    ///     switch flourish from this, so the persona shows the crossing coming
    ///     rather than snapping at the end of a silent two seconds.
    ///   - onDrag: where the persona was dragged to, in scene coordinates. Nil
    ///     disables repositioning -- which is right in a box, where there is
    ///     nowhere to put her that the stage has not already decided.
    func personaHold(target: Entity,
                     onTap: (() -> Void)?,
                     onHold: @escaping () -> Void,
                     onDrag: ((SIMD3<Float>) -> Void)? = nil,
                     onDragEnded: (() -> Void)? = nil,
                     progress: @escaping (Float) -> Void) -> some View {
        modifier(PersonaHoldModifier(target: target,
                                     onTap: onTap,
                                     onHold: onHold,
                                     onDrag: onDrag,
                                     onDragEnded: onDragEnded,
                                     progress: progress))
    }
}

private struct PersonaHoldModifier: ViewModifier {
    let target: Entity
    let onTap: (() -> Void)?
    let onHold: () -> Void
    let onDrag: ((SIMD3<Float>) -> Void)?
    /// Called once when a reposition finishes. Where she was LET GO is what
    /// gets remembered; where she passed through on the way is not.
    let onDragEnded: (() -> Void)?
    let progress: (Float) -> Void

    /// Two seconds, from Valinor, judged on a headset.
    private static let holdDuration: TimeInterval = 2.0

    /// How far a press has to travel, in metres, before it stops being a press.
    /// Valinor's number, judged on a headset: small enough that a deliberate
    /// move registers immediately, large enough that the hand drift in a
    /// two-second hold does not cancel the hold.
    private static let dragThreshold: Float = 0.03

    @State private var pressStarted: Date?
    /// Where the persona was when the press landed, and the offset from the
    /// pinch to her centre. Kept so she moves WITH the hand rather than
    /// snapping her centre onto it.
    @State private var grabOrigin: SIMD3<Float>?
    /// Set once a press has travelled far enough to be a drag. From then on it
    /// is a drag and nothing else -- no hold, no tap.
    @State private var dragging = false
    /// Set the moment the hold completes, so releasing afterwards does not also
    /// fire a tap and start a voice turn on the way out of the room.
    @State private var committed = false
    @State private var ramp: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(target)
                .onChanged { value in
                    if pressStarted == nil {
                        pressStarted = Date()
                        committed = false
                        dragging = false
                        // WHERE SHE WAS WHEN THE GRAB BEGAN, captured once.
                        // Everything below is measured from this rather than
                        // from where she is now -- see the note on
                        // `translation3D`.
                        grabOrigin = target.position(relativeTo: nil)
                        startRamp()
                    }

                    guard let grabOrigin, onDrag != nil else { return }
                    // THE TRANSLATION, NOT THE LOCATION, and this is the fix
                    // for a stutter that only appeared while moving.
                    //
                    // `location3D` is where the hand IS, and converting it out
                    // of `.local` means converting through the space of the
                    // entity being moved. Each frame's answer therefore depended
                    // on the previous frame's result: still hands converged,
                    // moving hands never settled. `translation3D` is how far
                    // the hand has come since the gesture began, which does not
                    // depend on where the persona has got to.
                    let moved = SIMD3<Float>(value.convert(value.translation3D,
                                                           from: .local, to: .scene))
                    let travelled = simd_length(moved)
                    if !dragging, travelled > Self.dragThreshold {
                        // It is a drag from here on. The hold ramp stops, because
                        // holding still is what a hold IS -- a person moving the
                        // persona across a room should not fall through into
                        // another space two seconds in.
                        dragging = true
                        stopRamp()
                        progress(0)
                    }
                    if dragging {
                        onDrag?(grabOrigin + moved)
                    }
                }
                .onEnded { _ in
                    stopRamp()
                    let held = pressStarted.map { Date().timeIntervalSince($0) } ?? 0
                    let wasDragging = dragging
                    pressStarted = nil
                    grabOrigin = nil
                    dragging = false
                    progress(0)
                    // A completed hold has already acted, and a drag has been
                    // acting the whole time. Releasing after either is just
                    // letting go, and must not also start a voice turn.
                    guard !committed else { committed = false; return }
                    guard !wasDragging else { onDragEnded?(); return }
                    guard held < Self.holdDuration else { return }
                    onTap?()
                }
        )
    }

    /// The visible half of the hold.
    ///
    /// Driven by a task rather than by the rig's own tick because the ramp
    /// belongs to the GESTURE: it has to start when the finger lands and stop
    /// when it lifts, neither of which the rig can see. It is also what fires
    /// `onHold` -- the crossing happens when the two seconds are up, not when
    /// the pinch is released, so the hold feels like it completed rather than
    /// like it was submitted.
    private func startRamp() {
        ramp?.cancel()
        ramp = Task { @MainActor in
            let started = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started)
                let t = min(1, elapsed / Self.holdDuration)
                progress(Float(t))
                if t >= 1 {
                    committed = true
                    progress(0)
                    onHold()
                    return
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func stopRamp() {
        ramp?.cancel()
        ramp = nil
    }
}
