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

/// Namespace marker. Replaced by real entities in phase 1; a target with no
/// sources does not build, and an empty file is a clearer placeholder than a
/// premature type.
public enum HearthSpatial {
    /// The design document this target is built against.
    public static let designDocument = "wiki/raw/hearth-vision-design.md"
}
