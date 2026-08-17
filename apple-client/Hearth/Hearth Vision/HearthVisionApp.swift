//
//  HearthVisionApp.swift
//  Hearth Vision
//
//  The visionOS entry point, and the skeleton of the topology in
//  wiki/raw/hearth-vision-design.md section 1.
//
//  Five scenes are designed. Two exist here, which is phase 0's whole scope:
//  the pairing window and an empty main volume. The library volume, the
//  immersive house and the transcript window are named in SceneID below and
//  declared when the phase that needs them lands -- a scene with nothing to
//  stage is a scene that cannot be judged.
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

    /// Mirrors ServerConfig so pairing swaps the scene without a relaunch.
    /// ServerConfig is the store of record; this is the redraw trigger.
    @State private var ready = ServerConfig.shared.isConfigured && ServerConfig.shared.isPaired

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        // The launch scene, and deliberately first: design section 1 says the
        // volume opens alone. An unpaired headset still lands here and then
        // sends for the pairing window, rather than launching into a flat pane
        // and promoting to a volume afterwards.
        WindowGroup(id: SceneID.personaVolume) {
            MainVolume(viewModel: viewModel, ready: ready)
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

        // A plain 2D pane. Address then code, and in phase 1 it reuses
        // FirstRunView's flow reshaped for a floating window -- that view is in
        // the iOS target today and reads UIDevice.current.name for the pairing
        // call, so the reshape is a real port rather than a move.
        WindowGroup(id: SceneID.pairing) {
            PairingWindow()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 580)
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

    /// Phase 3: the journal shelf at full size.
    static let libraryVolume = "hearth.library-volume"
    /// Phase 4: the mixed immersive house.
    static let immersiveHouse = "hearth.immersive-house"
    /// Phase 5: history as a thing in the room, not a mode of the stage.
    static let transcript = "hearth.transcript"
}
