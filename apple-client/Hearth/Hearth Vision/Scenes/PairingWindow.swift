//
//  PairingWindow.swift
//  Hearth Vision
//
//  Address, then code. A plain 2D pane rather than a volume, because nothing
//  about typing an address wants depth.
//
//  Phase 0 stands the window up and stops there. Phase 1 makes it live by
//  reshaping FirstRunView's flow, and that is a port rather than a move: the
//  iOS view reads `UIDevice.current.name` for the pairing call, which does not
//  exist on visionOS, and its two-step layout assumes a phone-shaped column.
//  What DOES carry unchanged is the contract underneath it -- `Pairing.pair`
//  and `ServerConfig` are both in HearthCore already, and the notification the
//  app entry listens for is the same one the phone posts.
//
//  Why an explicit pane at all, rather than branching the volume's content:
//  design section 1 calls pairing its own scene, and the reason shows up in
//  phase 4. The volume dismisses when the immersive house opens. A pairing
//  flow living inside it would vanish mid-typing.
//

import SwiftUI
import HearthCore
import HearthUI

struct PairingWindow: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Find the house")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(HearthPalette.roast)

            Text("Hearth needs an address and a pairing code before it can open the volume.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(HearthPalette.fawn)
                .fixedSize(horizontal: false, vertical: true)

            Text("The flow lands in phase 1.")
                .font(.system(size: 12.5))
                .italic()
                .foregroundStyle(HearthPalette.fawn)
                .padding(.top, 6)
        }
        .padding(32)
        // Sized, not stretched. `.windowResizability(.contentSize)` sizes the
        // window to what this view asks for, so a maxHeight of .infinity here
        // does not fill a 580pt window -- it makes the window as tall as the
        // system will allow. The first run of this scene came up as a portrait
        // slab for exactly that reason.
        .frame(width: 396)
        // The brand surface, painted explicitly, as every iOS surface already
        // does. A window with no background of its own is dark glass, and
        // HearthPalette's ink is chosen against a painted surface rather than
        // against whatever shows through.
        //
        // WORTH KNOWING, and confirmed on the simulator rather than reasoned:
        // this renders EMBER, not cream. HearthPalette.isEmber asks
        // UITraitCollection for `userInterfaceStyle == .dark`, and visionOS
        // answers dark always -- it has no light appearance to switch to. So
        // `cream` resolves to EmberHex.cream (0x241B14) and `roast` to the
        // light ink, permanently, on this platform.
        //
        // That is self-consistent and readable, and it may even be the right
        // look for a headset. But it means the light-first brand the palette
        // calls non-negotiable can never appear here, and nothing decided that
        // -- it fell out of a trait query written for a phone. Phase 5 owns the
        // decision: accept ember as the headset's mode and say so in the
        // palette, or give visionOS its own resolution path.
        .background(HearthPalette.cream)
    }
}
