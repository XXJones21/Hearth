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
//  -- drag past a threshold to reposition the orb in the room -- fits here
//  later without changing the arbitration.
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
    func personaHold(target: Entity,
                     onTap: (() -> Void)?,
                     onHold: @escaping () -> Void,
                     progress: @escaping (Float) -> Void) -> some View {
        modifier(PersonaHoldModifier(target: target,
                                     onTap: onTap,
                                     onHold: onHold,
                                     progress: progress))
    }
}

private struct PersonaHoldModifier: ViewModifier {
    let target: Entity
    let onTap: (() -> Void)?
    let onHold: () -> Void
    let progress: (Float) -> Void

    /// Two seconds, from Valinor, judged on a headset.
    private static let holdDuration: TimeInterval = 2.0

    @State private var pressStarted: Date?
    /// Set the moment the hold completes, so releasing afterwards does not also
    /// fire a tap and start a voice turn on the way out of the room.
    @State private var committed = false
    @State private var ramp: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(target)
                .onChanged { _ in
                    guard pressStarted == nil else { return }
                    pressStarted = Date()
                    committed = false
                    startRamp()
                }
                .onEnded { _ in
                    stopRamp()
                    let held = pressStarted.map { Date().timeIntervalSince($0) } ?? 0
                    pressStarted = nil
                    progress(0)
                    // A completed hold has already acted. Releasing after it is
                    // just letting go, and must not also be a tap.
                    guard !committed else { committed = false; return }
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
