//
//  FirstRunView.swift
//  Hearth
//
//  What a phone shows before it has been told where the house is.
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
//  Replaced in area 4 by the real shell. The orb and the address field are the
//  parts that survive.
//

import SwiftUI
import HearthCore

struct FirstRunView: View {
    @State private var address = ServerConfig.shared.address

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Drawn from Resources/Personas/sulivan.json, decoded by the same
            // PersonaPalette decoder that handles the wire payload. Not the
            // brand fallback -- that would look deliberate and be wrong.
            PersonaOrb(state: .IDLE)
                .frame(width: 190, height: 190)

            VStack(spacing: 6) {
                Text("Hearth")
                    .font(.title2.weight(.semibold))
                Text(ServerConfig.shared.isConfigured
                     ? "Connecting to your house."
                     : "Where is your house?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                TextField("hostname or IP", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.body.monospaced())

                // Apply means redial, which is why it is a button and not an
                // onChange: the socket only reads the address when it dials.
                Button("Apply") { ServerConfig.shared.address = address }
                    .buttonStyle(.borderedProminent)
                    .disabled(address == ServerConfig.shared.address)

                Text(verbatim: "Port \(ServerConfig.defaultPort) unless you name another.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthPalette.cream)
    }
}

#Preview {
    FirstRunView()
}
