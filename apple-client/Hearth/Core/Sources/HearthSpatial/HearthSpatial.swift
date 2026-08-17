//
//  HearthSpatial.swift
//  HearthCore
//
//  The shared RealityKit layer, declared empty in phase 0 so the dependency
//  arrows are settled before there is code to argue about.
//
//  What lands here in phase 1 and after, per wiki/raw/hearth-vision-design.md:
//  the persona rig (orb body, glow billboard, face), PersonaFaceTexture and its
//  compute kernel, the behavior director and its primitive library, JournalBook
//  and JournalShelf, and CardOrbitLayout.
//
//  What does NOT land here: scenes. A WindowGroup, a volumetric window and an
//  ImmersiveSpace are host-shaped and belong to their app target. This target
//  holds entities, and an entity does not know which scene is staging it.
//
//  The target builds for iOS as well as visionOS on purpose. Nothing on iOS
//  imports it yet; the build gate is the point, because it is what keeps the
//  later iOS adoption of the RealityKit orb a target change rather than a
//  rewrite.
//

import os

/// Namespace marker, and the target's logging subsystem.
public enum HearthSpatial {
    /// The design document this target is built against.
    public static let designDocument = "wiki/raw/hearth-vision-design.md"

    public static let subsystem = "com.joshuajones.HearthVision"
}

/// The spatial layer's log.
///
/// `os.Logger` rather than `print`, and on this target that is not a style
/// preference. The Vision scheme runs WITHOUT a debugger attached, because
/// attaching one wedges launch on the device -- and with no debugger there is
/// no Xcode console, because `print` writes to stdout and stdout is not the
/// unified log. Anything worth reading on a headset has to go here, where
/// Console.app and `xcrun devicectl device console` can both see it.
///
/// Read it with:
///   xcrun devicectl device console --device <name> | grep HearthSpatial
let log = Logger(subsystem: HearthSpatial.subsystem, category: "HearthSpatial")
