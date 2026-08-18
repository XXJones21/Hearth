//
//  ClosureComponent.swift
//  HearthSpatial
//
//  Per-frame work that belongs to an ENTITY rather than to a host.
//
//  Ported from Apple's own samples -- "Creating a 3D painting space" carries
//  both halves verbatim, and "Displaying an entity that follows a person's view"
//  uses it for the head-follow smoothing. It looks like a framework type in
//  those samples and is not: it is about twenty lines of sample source, which is
//  why it is written here rather than imported.
//
//  WHY THIS EXISTS HERE, and it is the whole reason phase 4 can happen at all.
//  The rig used to be ticked by `content.subscribe(to: SceneEvents.Update.self)`
//  taken from the volume's RealityView, with the subscription stored on the rig.
//  A subscription belongs to the scene that issued it; the rig outlives every
//  host by design. So the moment the volume dismisses to make way for the
//  immersive house, the rig stops ticking -- no face, no travel, no particles --
//  and nothing reports an error. The persona simply freezes in the room.
//
//  Making each host take and release its own subscription would work and would
//  be wrong: it hands every future host a lifecycle it cannot see, and any
//  overlap ticks the rig twice a frame. RealityKit "automatically creates an
//  instance of every registered system for every scene", so a system keyed on a
//  component runs in WHATEVER scene the entity is currently in. The handover
//  then costs nothing: no host holds anything, nothing needs releasing, and
//  there is no window in which two hosts both tick.
//
//  The system registers itself from the component's initializer, which is the
//  sample's own trick and removes the last thing a host had to remember.
//

import Foundation
import RealityKit

/// Runs a closure once per frame for as long as the entity is in a scene.
public struct ClosureComponent: Component {
    /// Called with the seconds elapsed since the last frame.
    public let closure: (TimeInterval) -> Void

    /// - Important: capture weakly. The entity holds this component, and
    ///   anything that owns the entity and is captured strongly here is a
    ///   retain cycle -- which for the persona rig means the rig, its model,
    ///   its textures and its Metal pipeline all outlive the app's interest in
    ///   them.
    public init(closure: @escaping (TimeInterval) -> Void) {
        self.closure = closure
        ClosureSystem.registerSystem()
    }
}

/// Drives every `ClosureComponent` in the scene.
public struct ClosureSystem: System {
    private static let query = EntityQuery(where: .has(ClosureComponent.self))

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            entity.components[ClosureComponent.self]?.closure(context.deltaTime)
        }
    }
}
