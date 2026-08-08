//
//  SettingsSurface.swift
//  Hearth
//
//  Read-only mirror of Valar's `GET /settings/surface`
//  (Valar/valar/gateway/settings_api.py). Everything it returns is an env var
//  read once at Valar start, so there is NO setter anywhere in the protocol --
//  these rows are house settings, read-only on every client, and this file
//  deliberately has no write path.
//
//  `folders` is served for clients carrying the `files` capability. iOS does
//  not: those paths describe the Valar machine's disk, which this device
//  cannot reach and must not present as if it could. The key is ignored.
//
//  An older server without the route 404s; that degrades to the client-local
//  sections rather than showing an error, same as desktop.
//

import Foundation

struct SettingsSurface: Decodable {
    var connections: [Connection] = []
    var resolved: [Resolved] = []
    var server: Server?

    struct Connection: Decodable, Identifiable {
        var key: String = ""
        var name: String = ""
        var role: String = ""
        /// "live" or "off".
        var state: String = ""
        /// Resolved URL when live; the missing env vars when not.
        var detail: String = ""

        var id: String { key.isEmpty ? name : key }
        var isLive: Bool { state == "live" }
    }

    struct Resolved: Decodable {
        var label: String = ""
        var value: String = ""
        /// Non-empty when the running value differs from the code default.
        var drift: String = ""
    }

    struct Server: Decodable {
        var version: String = ""
        var port: Int = 0
        var brain_backend: String = ""
    }

    /// The two rows the Memory section shows. The rest of `resolved` backs the
    /// developer pane, which iOS does not carry.
    func resolvedValue(_ label: String) -> String? {
        resolved.first { $0.label == label }?.value
    }
}

@MainActor
final class SettingsSurfaceLoader: ObservableObject {
    @Published private(set) var surface: SettingsSurface?
    @Published private(set) var isLoading = false
    /// True when the server answered but has no such route (older Valar).
    @Published private(set) var unavailable = false

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = ServerConfig.shared.url("/settings/surface") else {
            unavailable = true
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                print("[Settings] /settings/surface -> HTTP \(code)")
                unavailable = true
                return
            }
            surface = try JSONDecoder().decode(SettingsSurface.self, from: data)
            unavailable = false
        } catch {
            print("[Settings] /settings/surface failed: \(error.localizedDescription)")
            unavailable = true
        }
    }
}
