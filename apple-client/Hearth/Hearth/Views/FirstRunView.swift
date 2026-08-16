//
//  FirstRunView.swift
//  Hearth
//
//  What a phone shows before it has been told where the house is, and before
//  the house has agreed to let it in.
//
//  This is the area 1 gate made visible, and it is the check that matters most
//  in the whole migration: the app draws the real Sulivan, from JSON inside the
//  bundle, with nothing listening on any port -- and it does not dial.
//
//  Every other check on the done list gives the same answer whether or not the
//  default host survived the scrub. This one does not. Run it on a network that
//  cannot reach the development machine, or with Valinor stopped: with the
//  literal intact, a first run against Valinor looks flawless and the product is
//  wearing someone else's memory, journal and personas.
//
//  TWO steps, because they are two different states and a client that conflates
//  them shows "connecting" forever instead of "you need to pair". Knowing where
//  the house is and being allowed through its door are not the same thing.
//

import SwiftUI
import HearthCore
import UIKit

struct FirstRunView: View {
    private enum Step { case address, pairing }

    @State private var address = ServerConfig.shared.address
    @State private var code = ""
    @State private var step: Step = ServerConfig.shared.isConfigured ? .pairing : .address
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Drawn from Resources/Personas/sulivan.json, decoded by the same
            // PersonaPalette decoder that handles the wire payload. Not the
            // brand fallback -- that would look deliberate and be wrong.
            PersonaOrb(state: .IDLE)
                .frame(width: 170, height: 170)

            VStack(spacing: 6) {
                Text("Hearth")
                    .font(.title2.weight(.semibold))
                Text(step == .address
                     ? "Where is your house?"
                     : "Let this phone in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Group {
                if step == .address { addressStep } else { pairingStep }
            }
            .padding(.horizontal, 32)

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(HearthPalette.ember)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .keyboardType(.URL)
                .font(.body.monospaced())

            Button("Continue") {
                problem = nil
                ServerConfig.shared.address = address
                step = .pairing
            }
            .buttonStyle(.borderedProminent)
            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)

            Text(verbatim: "Port \(ServerConfig.defaultPort) unless you name another.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Step two: the code

    private var pairingStep: some View {
        VStack(spacing: 10) {
            Text("On the machine running Hearth, open Settings and choose Pair a device. It will show a six-digit code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 2)

            TextField("000000", text: $code)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .onChange(of: code) { _, value in
                    // Digits only, six of them. The house wants exactly that,
                    // and a field that quietly accepts more produces a failure
                    // the person cannot see the cause of.
                    let digits = value.filter(\.isNumber)
                    if digits != value || digits.count > 6 {
                        code = String(digits.prefix(6))
                    }
                }

            Button(busy ? "Pairing…" : "Pair") { pair() }
                .buttonStyle(.borderedProminent)
                .disabled(busy || code.count != 6)

            Button("Change the address") {
                problem = nil
                code = ""
                step = .address
            }
            .font(.caption)
            .padding(.top, 2)
        }
    }

    private func pair() {
        busy = true
        problem = nil
        Task {
            do {
                // The phone's own name, so the house's device list answers the
                // only question it is ever asked: which of these is the one I
                // lost. "iPhone" three times over answers nothing.
                try await Pairing.pair(code: code, deviceName: UIDevice.current.name)
                // Ask for the voice permissions HERE, in one deliberate
                // moment right after the house let the phone in, instead of
                // two system alerts stacking on the first mic tap. Skipped
                // automatically once answered.
                await VoicePermissions.prime()
                // ServerConfig posts on the address path; pairing has to say so
                // itself, and it is the same signal -- the root view's question
                // is "can this phone talk to a house", not "which half changed".
                NotificationCenter.default.post(name: .hearthServerConfigured, object: nil)
            } catch {
                problem = error.localizedDescription
                code = ""
            }
            busy = false
        }
    }
}

#Preview {
    FirstRunView()
}
