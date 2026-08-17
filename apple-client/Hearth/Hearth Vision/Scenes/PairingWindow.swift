//
//  PairingWindow.swift
//  Hearth Vision
//
//  Address, then code. A plain 2D pane rather than a volume, because nothing
//  about typing an address wants depth.
//
//  TWO steps, because they are two different states and a client that conflates
//  them shows "connecting" forever instead of "you need to pair". Knowing where
//  the house is and being allowed through its door are not the same thing.
//
//  Vision-native rather than a reuse of the phone's FirstRunView, and the reason
//  is worth stating because the design proposed the reuse. The contract
//  underneath is genuinely shared and IS reused -- `ServerConfig`, `Pairing.pair`
//  and the `.hearthServerConfigured` notification are all HearthCore, and this
//  file adds no logic of its own. What does not carry is the chrome: the phone's
//  view is a full-screen column sized against a keyboard sliding up under it,
//  and this is a 396pt floating pane in front of a room. Two layouts, one flow.
//
//  Why an explicit scene at all, rather than branching the volume's content:
//  design section 1 calls pairing its own scene, and the reason shows up in
//  phase 4. The volume dismisses when the immersive house opens. A pairing flow
//  living inside it would vanish mid-typing.
//

import SwiftUI
import HearthCore
import HearthUI
import UIKit

struct PairingWindow: View {
    private enum Step { case address, pairing }

    @State private var address = ServerConfig.shared.address
    @State private var code = ""
    @State private var step: Step = ServerConfig.shared.isConfigured ? .pairing : .address
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 20) {
            // Drawn from Resources/Personas/sulivan.json inside the bundle, by
            // the same decoder that handles the wire payload. The headset shows
            // the real persona before it has anywhere to dial -- which is the
            // check this screen exists to make visible.
            PersonaOrb(state: .IDLE)
                .frame(width: 130, height: 130)

            VStack(spacing: 5) {
                Text("Hearth")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(HearthPalette.roast)
                Text(step == .address ? "Where is your house?" : "Let this headset in.")
                    .font(.callout)
                    .foregroundStyle(HearthPalette.fawn)
            }

            Group {
                if step == .address { addressStep } else { pairingStep }
            }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(HearthPalette.ember)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(32)
        // Sized, not stretched. `.windowResizability(.contentSize)` sizes the
        // window to what this view asks for, so a maxHeight of .infinity here
        // would not fill a 580pt window -- it would make the window as tall as
        // the system allows. The first run of this scene came up as a portrait
        // slab for exactly that reason.
        .frame(width: 396)
        // The brand surface, painted explicitly, as every iOS surface does. A
        // window with no background of its own is dark glass, and this palette's
        // ink is chosen against a painted surface rather than against whatever
        // shows through.
        //
        // WORTH KNOWING, and confirmed on the simulator rather than reasoned:
        // this renders EMBER, not cream. HearthPalette.isEmber asks
        // UITraitCollection for `userInterfaceStyle == .dark`, and visionOS
        // answers dark always -- it has no light appearance to switch to. So
        // `cream` resolves to EmberHex.cream (0x241B14) and `roast` to the light
        // ink, permanently, on this platform.
        //
        // That is self-consistent and readable, and it may even be the right
        // look for a headset. But it means the light-first brand the palette
        // calls non-negotiable can never appear here, and nothing decided that
        // -- it fell out of a trait query written for a phone. Phase 5 owns the
        // decision: accept ember as the headset's mode and say so in the
        // palette, or give visionOS its own resolution path.
        .background(HearthPalette.cream)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // MARK: - Step one: the address

    private var addressStep: some View {
        VStack(spacing: 10) {
            TextField("hostname or IP", text: $address)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .onSubmit(commitAddress)

            Button("Continue", action: commitAddress)
                .buttonStyle(.borderedProminent)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)

            Text(verbatim: "Port \(ServerConfig.defaultPort) unless you name another.")
                .font(.caption)
                .foregroundStyle(HearthPalette.fawn)
        }
    }

    private func commitAddress() {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        problem = nil
        ServerConfig.shared.address = trimmed
        step = .pairing
    }

    // MARK: - Step two: the code

    private var pairingStep: some View {
        VStack(spacing: 10) {
            Text("On the machine running Hearth, open Settings and choose Pair a device. It will show a six-digit code.")
                .font(.caption)
                .foregroundStyle(HearthPalette.fawn)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TextField("000000", text: $code)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .onChange(of: code) { _, value in
                    // Digits only, six of them. The house wants exactly that,
                    // and a field that quietly accepts more produces a failure
                    // whose cause the person cannot see.
                    let digits = value.filter(\.isNumber)
                    if digits != value || digits.count > 6 {
                        code = String(digits.prefix(6))
                    }
                }
                .onSubmit(pair)

            Button(busy ? "Pairing..." : "Pair") { pair() }
                .buttonStyle(.borderedProminent)
                .disabled(busy || code.count != 6)

            Button("Change the address") {
                problem = nil
                code = ""
                step = .address
            }
            .font(.caption)
        }
    }

    private func pair() {
        guard !busy, code.count == 6 else { return }
        busy = true
        problem = nil
        Task {
            do {
                // The headset's own name, so the house's device list answers the
                // only question it is ever asked: which of these is the one I
                // lost.
                _ = try await Pairing.pair(code: code, deviceName: UIDevice.current.name)
                // Ask for the voice permissions HERE, in one deliberate moment
                // right after the house let the headset in, instead of two
                // system alerts stacking on the first pinch of the bead.
                await VoicePermissions.prime()
                // ServerConfig posts on the address path; pairing has to say so
                // itself, and it is the same signal -- the app's question is
                // "can this device talk to a house", not "which half changed".
                NotificationCenter.default.post(name: .hearthServerConfigured, object: nil)
            } catch {
                problem = error.localizedDescription
                code = ""
            }
            busy = false
        }
    }
}
