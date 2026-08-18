//
//  PersonaModelView.swift
//  Hearth
//
//  The `glb_animated` renderer: Selene, and Sage when she arrives. A
//  RealityView holding one model entity whose animation changes with the
//  conversation state.
//
//  Why USDZ and not the GLB every other client uses: RealityKit has no glTF
//  importer on iOS or visionOS. The clips are converted on the Mac by
//  scripts/glb_to_usdz.py and served from Valar beside the GLB.
//
//  Why one file per state: USD binds exactly ONE animation per skeleton
//  (`rel skel:animationSource`), so Quest's "one file, four tracks" has no USD
//  equivalent. The library is assembled here instead -- load idle for the mesh,
//  take one AnimationResource from each other file, and play by state name.
//  From the caller's side the contract is Quest's: a state goes in, the right
//  clip plays.
//
//  Framing waits for playback to settle and then fits ONCE, by standing height,
//  from visualBounds -- measured late so the pose, not the bind pose, sets the
//  size. Do not try to measure the skeleton's joints directly: a SkeletalPose's
//  jointTransforms are parent-relative, so treating them as skeleton-space
//  points collapses the rig onto the origin and the fit scale explodes.
//
//  The two things that make skeletal animation work at all here, both learned
//  the hard way and both easy to undo by accident:
//    1. Every clip file must share ONE root prim name. An imported clip is an
//       AnimationGroup whose bindTarget is a prim path, resolved relative to
//       the entity it plays on, so clips are only portable between files when
//       that path is identical. See unify_root_prim in glb_to_usdz.py.
//    2. Play on the LOADED ROOT, never on the SkelRoot. The bind path starts
//       at the root prim; played deeper it matches nothing and the character
//       stands still while reporting playing=true.
//

import SwiftUI
import HearthCore
import RealityKit

public struct PersonaModelView: View {
    public let visualization: PersonaVisualization
    public let state: HearthState

    /// Explicit: a public struct's memberwise init is internal, and the iOS
    /// main view mounts this whenever the persona asks for `glb_animated`.
    public init(visualization: PersonaVisualization, state: HearthState) {
        self.visualization = visualization
        self.state = state
    }

    @State private var loader = PersonaModelLoader()
    @State private var failed = false

    public var body: some View {
        ZStack {
            RealityView { content in
                let root = Entity()
                content.add(root)
                await loader.load(visualization: visualization, into: root)
                failed = !loader.isLoaded
            } update: { _ in
                loader.play(state: state)
            }
            .opacity(loader.isLoaded ? 1 : 0)

            if !loader.isLoaded {
                ProgressView()
                    .tint(HearthPalette.fennec)
                    .opacity(failed ? 0 : 1)
            }
        }
        .task(id: state) { loader.play(state: state) }
    }
}

/// Owns the entity, its animation library and the one-shot framing pass.
@Observable
@MainActor
public final class PersonaModelLoader {
    /// Public because the SPATIAL rig hosts this too, not just the phone's
    /// view: `PersonaRig` keeps its orb on screen until the model is actually
    /// standing, so a slow download shows a bead rather than an empty stage.
    public private(set) var isLoaded = false

    public init() {}

    /// Called once the one-shot framing pass has run and the model's size is
    /// FINAL.
    ///
    /// Framing happens 800ms after the model is added, so anything measured at
    /// `load`'s return is measured against the un-fitted model -- which for the
    /// rig's collision box meant a pinch target several times the size of the
    /// figure standing in it. The phone leaves this nil: its view has nothing
    /// to re-measure.
    public var onFramed: (() -> Void)?

    private var model: Entity?
    /// Where clips are played: the loaded root, where their bind paths start.
    private var animationTarget: Entity?
    private var animations: [String: AnimationResource] = [:]
    private var current: String?
    private var framingTask: Task<Void, Never>?
    private var playback: AnimationPlaybackController?
    private var loopTask: Task<Void, Never>?

    /// - Parameters:
    ///   - fitHeight: how tall the model should end up, IN THE UNITS OF THE
    ///     ENTITY IT IS ADDED TO. The phone's stage is a RealityView of its own
    ///     whose root sits at identity, where 1.34 is full-length-mirror
    ///     framing; a spatial host parents this inside a rig with a scale of
    ///     its own, and the fit has to mean the same thing there. It was a
    ///     literal in `scheduleFraming` until the headset needed a second one.
    ///   - fitWidth: the guard that stops a wide pose overflowing.
    public func load(visualization: PersonaVisualization,
                     into root: Entity,
                     fitHeight: Float = 1.34,
                     fitWidth: Float = 1.15) async {
        guard let idleURL = visualization.clipURL(for: "idle") else { return }

        // The idle file carries the mesh and skeleton; everything else is
        // wanted only for its animation.
        guard let entity = await Self.loadEntity(from: idleURL) else { return }

        // Config rotation, so a model authored facing away can be corrected
        // per-persona without touching code.
        if visualization.rotationY != 0 {
            entity.transform.rotation = simd_quatf(
                angle: Float(visualization.rotationY) * .pi / 180,
                axis: [0, 1, 0]
            )
        }

        var library: [String: AnimationResource] = [:]

        // A single file carrying every clip -- what Reality Composer Pro
        // exports, and what Quest gets natively from glTF -- is the preferred
        // shape. Take the whole library by NAME and skip the per-state loads
        // entirely. Names are normalised the way Quest's track map does it,
        // including Talking -> speaking.
        for animation in entity.availableAnimations {
            guard let name = animation.name, !name.isEmpty else { continue }
            if let state = Self.stateForClip(name) {
                library[state] = animation
            }
        }
        if library.count > 1 {
            print("[Persona] single-file animation library: \(library.keys.sorted().joined(separator: ", "))")
        }

        // Otherwise this is one of the per-clip USDZ files, whose sole
        // animation is the idle pose; the rest arrive below.
        if library.isEmpty, let idle = entity.availableAnimations.first {
            library["idle"] = idle
        }

        // Load the remaining states concurrently; each contributes exactly one
        // clip. They share Selene's skeleton, so the resource retargets.
        await withTaskGroup(of: (String, AnimationResource?).self) { group in
            for state in visualization.orderedStates where library[state] == nil {
                guard let url = visualization.clipURL(for: state) else { continue }
                group.addTask {
                    let clip = await Self.loadEntity(from: url)?.availableAnimations.first
                    return (state, clip)
                }
            }
            for await (state, clip) in group {
                if let clip { library[state] = clip }
            }
        }

        model = entity
        // The LOADED ROOT, not the skeleton. An imported clip arrives as an
        // AnimationGroup whose bindTarget is a prim path ("selene"), resolved
        // RELATIVE TO whatever entity it is played on. Played on the SkelRoot
        // that path matches nothing and the clip drives nothing at all --
        // playing=true, real duration, a completely still character. Played on
        // the root the path resolves and RealityKit routes it to the skeleton
        // itself. This is why every clip must share one root prim name; see
        // unify_root_prim in scripts/glb_to_usdz.py.
        animationTarget = entity
        animations = library
        root.addChild(entity)
        isLoaded = true

        print("[Persona] model loaded, clips: \(library.keys.sorted().joined(separator: ", "))")
        print("[Persona] entity tree:")
        Self.describe(entity)
        Self.describeAnimations(library)

        play(state: .IDLE)
        scheduleFraming(entity: entity, fitHeight: fitHeight, fitWidth: fitWidth)
    }

    /// Take the model down and forget it.
    ///
    /// Needed the moment a persona can be switched WHILE the stage is up:
    /// without it, choosing Selene and then Sulivan leaves Selene standing in
    /// the scene behind the orb, and choosing Selene again stacks a second
    /// copy on the first. The phone never needed this because its host view is
    /// rebuilt around a fresh loader; the rig outlives the persona.
    public func unload() {
        framingTask?.cancel(); framingTask = nil
        loopTask?.cancel(); loopTask = nil
        playback?.stop(); playback = nil
        model?.removeFromParent()
        model = nil
        animationTarget = nil
        animations = [:]
        current = nil
        isLoaded = false
    }

    /// Swap the playing clip. Falls back to idle for any state the persona did
    /// not ship, exactly as Quest's track map does.
    public func play(state: HearthState) {
        guard let target = animationTarget else { return }
        let key = Self.animationKey(for: state)
        let resolved = animations[key] != nil ? key : "idle"
        guard resolved != current, let clip = animations[resolved] else { return }
        current = resolved
        // The raw resource; looping is arranged in loopIfNeeded instead of
        // through `AnimationResource.repeat()`.
        let controller = target.playAnimation(clip, transitionDuration: 0.35, startsPaused: false)
        playback = controller
        print("[Persona] play \(resolved) on '\(target.name)' -> playing=\(controller.isPlaying) duration=\(String(format: "%.1f", controller.duration))s")
        loopIfNeeded(clip: clip, on: target, duration: controller.duration)
    }

    /// Restart the clip as it ends. Crude next to a looping resource, but it
    /// keeps the raw AnimationResource that actually drives the skeleton.
    private func loopIfNeeded(clip: AnimationResource, on target: Entity, duration: TimeInterval) {
        loopTask?.cancel()
        guard duration.isFinite, duration > 0.1 else { return }
        let key = current
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, duration - 0.2) * 1_000_000_000))
                guard !Task.isCancelled, let self, self.current == key else { return }
                self.playback = target.playAnimation(clip, transitionDuration: 0.2, startsPaused: false)
            }
        }
    }

    /// What RealityKit actually BUILT from the USD, which is not visible from
    /// the entity tree. A skeletal clip should arrive as a group whose members
    /// bind to `.jointTransforms`; a clip that only drives node transforms
    /// binds to `.transform` instead and animates entities nothing is skinned
    /// to -- which looks identical from the outside (playing=true, real
    /// duration) and leaves the mesh in its bind pose.
    private static func describeAnimations(_ library: [String: AnimationResource]) {
        for (state, clip) in library.sorted(by: { $0.key < $1.key }) {
            let definition = clip.definition
            print("[Persona] clip '\(state)' -> \(type(of: definition))")
            describeDefinition(definition, indent: "    ")
        }
    }

    private static func describeDefinition(_ definition: any AnimationDefinition, indent: String) {
        if let group = definition as? AnimationGroup {
            print("[Persona] \(indent)group of \(group.group.count)")
            for member in group.group.prefix(6) {
                describeDefinition(member, indent: indent + "  ")
            }
            return
        }
        let target = String(describing: definition.bindTarget)
        print("[Persona] \(indent)\(type(of: definition)) bindTarget=\(target)")
    }

    private static func describe(_ entity: Entity, depth: Int = 0) {
        let pad = String(repeating: "  ", count: depth)
        let skel = entity.components.has(SkeletalPosesComponent.self) ? " [skeleton]" : ""
        let anims = entity.availableAnimations.isEmpty ? "" : " [\(entity.availableAnimations.count) anim]"
        print("[Persona]   \(pad)\(entity.name.isEmpty ? "<unnamed>" : entity.name)\(skel)\(anims)")
        entity.children.forEach { describe($0, depth: depth + 1) }
    }

    /// Clip name -> state, matching Quest's buildAnimationTrackMap. A bind
    /// pose is not a state and must never be selectable.
    private static func stateForClip(_ clipName: String) -> String? {
        switch clipName.trimmingCharacters(in: .whitespaces).lowercased() {
        case "idle":                 return "idle"
        case "listening":            return "listening"
        case "thinking":             return "thinking"
        case "talking", "speaking":  return "speaking"
        default:                     return nil
        }
    }

    private static func animationKey(for state: HearthState) -> String {
        switch state {
        case .LISTENING: return "listening"
        case .THINKING:  return "thinking"
        case .SPEAKING:  return "speaking"
        default:         return "idle"
        }
    }

    private static func loadEntity(from url: URL) async -> Entity? {
        do {
            let local = try await PersonaAssetCache.shared.localURL(for: url)
            return try await Entity(contentsOf: local)
        } catch {
            print("[Persona] failed to load \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Framing

    /// Fit ONCE from the posed skeleton. A static bounding box lies for an
    /// animated skinned model: the clip's Spine.scale tracks reshape the
    /// skeleton every frame, and measuring during the T-pose catches spread
    /// arms and under-frames. Wait for the pose to settle, then measure the
    /// joints themselves.
    private func scheduleFraming(entity: Entity, fitHeight: Float, fitWidth: Float) {
        framingTask?.cancel()
        framingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }

            // IN THE PARENT'S SPACE, not the scene's.
            //
            // `relativeTo: nil` measures in SCENE space, which is identical
            // here only while the chain above the model is at identity -- true
            // of the phone's own RealityView and of nothing else. In the
            // headset's volume the model hangs inside a rig scaled to 0.22
            // inside a stage root that rescales with the window, so a scene-
            // space fit solved for "1.34 metres in the ROOM" and put a
            // life-size person inside a box 80cm wide. Her collision box came
            // with her, which is why every pinch in the volume stopped landing
            // on anything else.
            //
            // Measured against the parent, `fitHeight` means what its caller
            // said it meant, and a window resize cannot change the answer.
            let bounds = entity.visualBounds(relativeTo: entity.parent)
            let size = bounds.extents
            guard size.y > 0.0001 else { return }

            // Fill most of the stage by standing HEIGHT -- full-length mirror
            // framing -- with a width guard so a wide pose cannot overflow.
            //
            // Measured from visualBounds, NOT from the skeleton's joints. A
            // SkeletalPose's jointTransforms are each relative to their PARENT
            // JOINT, so treating them as skeleton-space points collapses the
            // whole rig onto the origin and the fit scale explodes. Composing
            // them properly needs the joint parent table; the mesh bounds
            // already account for the pose and cost nothing.
            let scale = min(fitHeight / size.y, fitWidth / max(size.x, 0.0001))
            entity.scale *= SIMD3<Float>(repeating: scale)

            let center = bounds.center * scale
            entity.position -= SIMD3<Float>(center.x, center.y, 0)

            onFramed?()
        }
    }

}

// MARK: - Asset cache

/// Persona models are tens of megabytes and change rarely, so they are fetched
/// once and read from disk after that. A failed download leaves any cached copy
/// in place -- an offline phone should still show Selene.
public actor PersonaAssetCache {
    public static let shared = PersonaAssetCache()

    private lazy var root: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonaModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    public func localURL(for remote: URL) async throws -> URL {
        let name = remote.lastPathComponent

        // A bundled copy wins: it needs no network and no cache warm-up. This
        // is how the models are tested before Valar's checkout has them, and
        // it stays useful afterwards as the offline floor for shipped
        // personas. The server copy remains canonical for anything not bundled.
        if let bundled = Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
                                         withExtension: (name as NSString).pathExtension) {
            return bundled
        }

        let destination = root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        var request = URLRequest(url: remote)
        ServerConfig.shared.authorize(&request)
        request.timeoutInterval = 60
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temp)
            throw URLError(.badServerResponse)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }
}
