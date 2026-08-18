//
//  HearthVisionApp.swift
//  Hearth Vision
//
//  The visionOS entry point, and the skeleton of the topology in
//  wiki/raw/hearth-vision-design.md section 1.
//
//  Five scenes are designed. Two exist: the pairing window and the main volume.
//  The library volume, the immersive house and the transcript window are named
//  in SceneID below and declared when the phase that needs them lands -- a scene
//  with nothing to stage is a scene that cannot be judged.
//
//  What this file does NOT carry, and the iOS entry point does: an onOpenURL
//  handler. `hearth://talk` is the QuickTalk widget's deep link, the widget
//  extension is an iOS target, and two apps registering one scheme is an
//  ambiguity rather than a feature. If the headset ever grows a widget the
//  scheme comes back with it.
//
//  The paired gate is the iOS one verbatim, and for the same reason: a headset
//  is never the machine running the backend, so an address with no token earns
//  a socket closed with 1008 and an orb that sits at "connecting" forever.
//  Both halves, or the pairing window owns the session.
//

import SwiftUI
import HearthCore
import HearthUI
import HearthSpatial

@main
struct HearthVisionApp: App {
    /// Built once for the process, and hoisted here rather than owned by a
    /// scene. Design section 1's one-scene rule turns on this: the entity world
    /// outlives any host that stages it, and in phase 4 the same world has to
    /// survive the volume dismissing as the immersive house opens.
    ///
    /// ChatViewModel dials in its initializer, so a view that built its own
    /// would open a second socket every time SwiftUI rebuilt the body.
    @StateObject private var viewModel = ChatViewModel()

    /// The entity world, hoisted for the same reason as the view model and with
    /// more at stake. In phase 4 the volume dismisses while the immersive house
    /// opens, and the SAME rig has to survive that handover -- a rig owned by
    /// the volume would be destroyed at precisely the moment the design asks it
    /// to travel. Hosts attach and release it; nobody but this file owns it.
    ///
    /// `embedCamera: false` is not a preference. On visionOS the system owns
    /// the viewer pose, and an app-created camera in a volumetric window
    /// crashes the device at launch.
    @StateObject private var rig = PersonaRig(embedCamera: false)

    /// Mirrors ServerConfig so pairing swaps the scene without a relaunch.
    /// ServerConfig is the store of record; this is the redraw trigger.
    @State private var ready = ServerConfig.shared.isConfigured && ServerConfig.shared.isPaired

    /// Whether the room is open. The volume dismisses while it is, per design
    /// section 1, and returns on exit.
    @State private var immersive = false

    /// Where the persona was, in the ROOM's coordinates, at the moment of
    /// crossing. Nil until captured; the room waits for it.
    ///
    /// See `enterImmersive` for why the capture has to happen in the one moment
    /// it does.
    @State private var spawn: simd_float4x4?

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some Scene {
        // The launch scene, and deliberately first: design section 1 says the
        // volume opens alone. An unpaired headset still lands here and then
        // sends for the pairing window, rather than launching into a flat pane
        // and promoting to a volume afterwards.
        WindowGroup(id: SceneID.personaVolume) {
            MainVolume(viewModel: viewModel, rig: rig, ready: ready,
                       onEnterImmersive: enterImmersive)
                .onAppear {
                    guard !ready else { return }
                    openWindow(id: SceneID.pairing)
                }
                .onReceive(NotificationCenter.default.publisher(for: .hearthServerConfigured)) { _ in
                    let paired = ServerConfig.shared.isConfigured && ServerConfig.shared.isPaired
                    // This notification also fires on the address step, when
                    // there is still no token. Dialling then earns the 1008 and
                    // a reconnect loop running behind a pairing window the
                    // person is still using.
                    guard paired else { return }
                    ready = true
                    dismissWindow(id: SceneID.pairing)
                    // The view model was built before an address existed, so
                    // its socket was never dialled. Now there is somewhere to
                    // dial and a token to dial it with.
                    Task { await viewModel.redial() }
                }
        }
        .windowStyle(.volumetric)
        // Waist-to-chest at arm's length, and a cube because the rig turns.
        // Phase 1 sets the persona low in the box, carrying the iOS
        // CardOrbitLayout.orbY = -0.22 reasoning: low means it can be set on a
        // real table.
        .defaultSize(width: 0.8, height: 0.8, depth: 0.8, in: .meters)

        // A plain 2D pane. Address then code, against the same HearthCore
        // contract the phone pairs through; only the chrome is Vision-native.
        // See PairingWindow for why the phone's view was not reused directly.
        WindowGroup(id: SceneID.pairing) {
            PairingWindow()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 580)
        // Onboarding, and the platform has names for exactly that. Pairing is
        // a one-time action: restoring it would put a paired headset back in
        // front of a form it has already filled in, and launching it would do
        // the same on every cold start. The volume sends for this window when
        // it is actually needed, which is the only time it should appear.
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        // The room. Design section 1's expansion, reached by holding the
        // persona and left the same way.
        ImmersiveSpace(id: SceneID.immersiveHouse) {
            ImmersiveHouse(viewModel: viewModel, rig: rig,
                           spawn: spawn, onLeave: leaveImmersive)
                .onDisappear {
                    // THE OTHER WAY OUT, and the one that is not ours.
                    //
                    // A person can close any scene at any time -- the Digital
                    // Crown, the Home button -- and none of that runs the hold
                    // gesture. Without this the app is left believing it is
                    // still in the room: the flag stays true, the volume never
                    // comes back, and there is nothing on screen to bring it
                    // back with.
                    //
                    // `leaveImmersive` clears the flag BEFORE it awaits, so a
                    // deliberate exit reaches here with it already false and
                    // this does nothing. Anything else is the system's doing.
                    guard immersive else { return }
                    immersive = false
                    spawn = nil
                    openWindow(id: SceneID.personaVolume)
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }

    // MARK: - Crossing between the box and the room

    /// ORDER MATTERS, and it is the platform's rule rather than a preference:
    /// an app cannot close its last scene, so the space has to be open before
    /// the volume goes. Apple states it directly -- put the dismiss inside the
    /// task so it waits for the asynchronous open, or the system opens the space
    /// and leaves the window up.
    private func enterImmersive() {
        guard !immersive else { return }
        Task {
            switch await openImmersiveSpace(id: SceneID.immersiveHouse) {
            case .opened:
                immersive = true
                // THE CAPTURE, and there is exactly one moment it can happen.
                //
                // RealityKit's two named coordinate spaces are `.scene`, whose
                // origin is the centre-back of the volumetric window, and
                // `.immersiveSpace`, whose origin is the point on the ground
                // below you. Converting between them is how the persona leaves
                // the box at the place she was actually standing rather than at
                // a guess -- and `.immersiveSpace` only means anything WHILE a
                // space is open.
                //
                // So: after the open has returned, while the rig is still in the
                // volume's scene, and before the window goes. Both scenes are
                // alive for exactly this instant. The room's own view waits for
                // this value rather than placing her itself, which is what
                // keeps it from grabbing the entity before the read.
                //
                // Apple's own sample composes `content.transform(from:to:)`
                // instead, which returns a DOUBLE-precision AffineTransform3D
                // and is risk point 1 in Valinor's handoff. This overload
                // returns a float4x4 and skips the conversion entirely.
                spawn = rig.transformInImmersiveSpace()
                dismissWindow(id: SceneID.personaVolume)
            case .userCancelled, .error:
                // The person declined, or the system refused. Staying in the box
                // is the correct outcome and needs no recovery.
                break
            @unknown default:
                break
            }
        }
    }

    /// The same rule mirrored: bring the volume back BEFORE the space closes.
    private func leaveImmersive() {
        guard immersive else { return }
        // Cleared FIRST, before the await, so the `onDisappear` above can tell
        // our own exit from the person closing the space themselves. Setting it
        // after would have both paths firing and two volumes opening.
        immersive = false
        Task {
            openWindow(id: SceneID.personaVolume)
            await dismissImmersiveSpace()
            // The volume places the persona at its own fixed spot, so there is
            // nothing to carry back. Cleared so a second crossing captures
            // afresh rather than reusing where she was the first time.
            spawn = nil
        }
    }
}

/// Scene identifiers, named once.
///
/// Every id the design calls for, including the three with no scene behind them
/// yet. They are here rather than spelled at each call site because
/// `openWindow(id:)` takes a string and a typo in one is a window that silently
/// never opens.
enum SceneID {
    /// The resting state: the persona rig, its cards, a compact journal shelf.
    static let personaVolume = "hearth.persona-volume"
    /// Address then code, shown while unpaired.
    static let pairing = "hearth.pairing"

    // Declared in the phase that stages them. See design sections 1 and 8.

    /// NOT USED. Design section 1 wanted the library at full size in its own
    /// volumetric window; on the device a second volume sits in FRONT of the
    /// main one and obscures it, which is the wrong trade for a library you
    /// open mid-conversation. The library lives in the main volume's centre
    /// slot instead. Kept named so the next person to reach for a second volume
    /// finds out here rather than on a headset.
    static let libraryVolume = "hearth.library-volume"
    /// Phase 4: the mixed immersive house.
    static let immersiveHouse = "hearth.immersive-house"
    /// Phase 5: history as a thing in the room, not a mode of the stage.
    static let transcript = "hearth.transcript"
}
