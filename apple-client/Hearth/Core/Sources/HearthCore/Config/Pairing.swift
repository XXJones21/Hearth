//
//  Pairing.swift
//  Hearth
//
//  Trading a six-digit code for a device token.
//
//  The house exempts loopback and requires a token from everything else, and a
//  phone is never loopback -- it is never the machine running the backend. So
//  pairing is not an optional hardening step on this client, it is how the
//  phone gets in at all.
//
//  Deliberately the ONE request in the client that does not carry a token:
//  `/pair` is the door, and a device asking to be let in has nothing to present
//  yet. Everything after this goes through ServerConfig's authorized builders.
//

import Foundation

public enum PairingError: Error, LocalizedError {
    case notConfigured
    case rejected
    case unreachable(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No house address yet."
        case .rejected:
            // The house answers one way for wrong, expired and locked-out,
            // because telling them apart is a free hint to anyone guessing.
            // The client must not invent a more specific story than it was told.
            return "That code was not accepted. Ask the house for a new one."
        case .unreachable(let detail):
            return detail
        }
    }
}

public enum Pairing {
    /// Redeem a code. On success the token is stored and every later request
    /// carries it.
    ///
    /// The device name is what the person will see in the house's device list
    /// when they come to revoke something, so it should be the phone's name
    /// rather than "iPhone" -- "which of these three is the one I lost" is the
    /// only question that list has to answer.
    @discardableResult
    public static func pair(code: String, deviceName: String) async throws -> String {
        guard let url = ServerConfig.shared.url("/pair") else {
            throw PairingError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "device_name": deviceName,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // A house that cannot be reached and a house that refuses are
            // different problems with different fixes -- check the address
            // versus check the code -- so they must not share a message.
            throw PairingError.unreachable(
                "Could not reach \(ServerConfig.shared.address). Check the address."
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw PairingError.unreachable("The house gave an answer this app could not read.")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 {
                // A house too old to know about pairing. Saying so beats
                // "that code was wrong" when the code was never the problem.
                throw PairingError.unreachable(
                    "That house does not support pairing yet. Update Hearth on the machine running it."
                )
            }
            throw PairingError.rejected
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = payload["token"] as? String, !token.isEmpty else {
            throw PairingError.unreachable("The house accepted the code but sent no token.")
        }

        ServerConfig.shared.deviceToken = token
        return token
    }

    /// Forget this device's token. The house still lists it until someone
    /// revokes it there -- this is the local half only, and the copy around it
    /// should not promise more than that.
    public static func forget() {
        ServerConfig.shared.deviceToken = nil
    }
}
