//
//  MainVolume.swift
//  Hearth Vision
//
//  The resting state, and phase 0's version of it: an empty stage that proves
//  the target links, launches and knows whether it is paired.
//
//  Design section 1 fills this box in phase 1 and after: the persona rig low in
//  the volume, cards billboarding beside it, a compact journal shelf, the
//  composer as a bottom ornament and house status as a top ornament. None of
//  that is here, and the placeholder says so rather than drawing a fake orb --
//  a stage that looks finished is a stage nobody checks.
//
//  It is a dumb host by design. Section 1's one-scene rule puts the entity
//  world at app level and has each host attach or release the shared root on
//  appear and dismiss, because in phase 4 this volume dismisses while the
//  immersive house takes the same world. A host that owned state would lose it
//  at exactly that moment.
//

import SwiftUI
import HearthCore
import HearthUI

struct MainVolume: View {
    @ObservedObject var viewModel: ChatViewModel

    /// Paired AND configured. The app owns this; the volume only renders it.
    let ready: Bool

    var body: some View {
        ZStack {
            if ready {
                stage
            } else {
                waiting
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Painted rather than left as glass, and it resolves to ember on this
        // platform -- see PairingWindow for the trait-query reason and the
        // phase 5 question it raises.
        //
        // Phase 1 replaces this whole view with a RealityView, where the
        // question does not arise: an entity brings its own material.
        .background(HearthPalette.cream)
    }

    /// Phase 1 replaces this with the RealityView hosting the persona rig.
    private var stage: some View {
        VStack(spacing: 10) {
            Text("Hearth")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text("The volume is standing. The house is not in it yet.")
                .font(.system(size: 15))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
            Text(status)
                .font(.system(size: 13))
                .foregroundStyle(HearthPalette.fawn)
                .padding(.top, 4)
        }
        .padding(28)
    }

    /// Shown while the pairing window has the session. Deliberately quiet: the
    /// person is being asked for something in another window, and a second
    /// surface competing for their attention is noise.
    private var waiting: some View {
        VStack(spacing: 8) {
            Text("Hearth")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(HearthPalette.roast)
            Text("Waiting to be told where the house is.")
                .font(.system(size: 14))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
        }
        .padding(28)
    }

    /// The socket, in words. Phase 0's one live signal, and the reason it is
    /// worth having: it is the proof that HearthCore's transport runs on xrOS
    /// and not merely that it compiles for it.
    private var status: String {
        switch viewModel.connectionStatus {
        case .connected:    return "Connected to the house."
        case .connecting:   return "Reaching for the house..."
        case .disconnected: return "The house is not answering."
        }
    }
}
