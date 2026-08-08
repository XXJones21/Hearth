//
//  AppsSurface.swift
//  Hearth
//
//  Read-only mirror of Valar's `GET /apps/surface`. Everything it returns is
//  DERIVED server-side from tools.yaml, card_catalog.yaml and each persona's
//  tool_grants.domains, so this file has no write path and the client invents
//  nothing -- same contract as SettingsSurface.
//
//  Apps ARE MCPs for our purposes (decided 2026-08-03). When Valar grows an
//  MCP client, discovered servers arrive as ordinary rows with `kind: "mcp"`
//  and nothing here changes. Do NOT special-case MCP on the phone.
//
//  An older server without the route 404s; that degrades to the On device
//  section alone rather than showing an error.
//

import Foundation

struct AppsSurface: Decodable {
    var apps: [App] = []
    var cards: [CardType] = []
    var personas: [String] = []
    var toolsEnabled: Bool = true

    private enum CodingKeys: String, CodingKey {
        case apps, cards, personas
        case toolsEnabled = "tools_enabled"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = (try? c.decode([App].self, forKey: .apps)) ?? []
        cards = (try? c.decode([CardType].self, forKey: .cards)) ?? []
        personas = (try? c.decode([String].self, forKey: .personas)) ?? []
        toolsEnabled = (try? c.decode(Bool.self, forKey: .toolsEnabled)) ?? true
    }

    struct App: Decodable, Identifiable {
        var key: String = ""
        var name: String = ""
        /// core | cli | local | mcp
        var kind: String = ""
        var tagline: String = ""
        var transport: String = ""
        var tools: [String] = []
        /// Tools beyond the ten the server sends.
        var more: Int = 0
        var cards: [String] = []
        /// Personas granted the domains this app covers.
        var who: [String] = []
        /// active | setup | available
        var state: String = ""
        /// read | write | control
        var risk: String = ""
        /// Env vars the app is waiting on, when `state` is setup.
        var needs: [String] = []
        /// Hearth core, which is always on.
        var locked: Bool = false

        var id: String { key.isEmpty ? name : key }

        // Decoded field by field, each falling back to its default. The
        // synthesized conformance fails the WHOLE payload on one type
        // mismatch -- `data_fields` arriving as prose rather than a list blanked
        // the entire page once -- and this surface is derived server-side from
        // three YAML files, so its shape will keep moving. One drifted field
        // should cost that field, not the screen.
        private enum CodingKeys: String, CodingKey {
            case key, name, kind, tagline, transport, tools, more
            case cards, who, state, risk, needs, locked
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = (try? c.decode(String.self, forKey: .key)) ?? ""
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
            tagline = (try? c.decode(String.self, forKey: .tagline)) ?? ""
            transport = (try? c.decode(String.self, forKey: .transport)) ?? ""
            tools = (try? c.decode([String].self, forKey: .tools)) ?? []
            more = (try? c.decode(Int.self, forKey: .more)) ?? 0
            cards = (try? c.decode([String].self, forKey: .cards)) ?? []
            who = (try? c.decode([String].self, forKey: .who)) ?? []
            state = (try? c.decode(String.self, forKey: .state)) ?? ""
            risk = (try? c.decode(String.self, forKey: .risk)) ?? ""
            needs = (try? c.decode([String].self, forKey: .needs)) ?? []
            locked = (try? c.decode(Bool.self, forKey: .locked)) ?? false
        }

        var kindLabel: String {
            switch kind {
            case "core":  return "built in"
            case "cli":   return "CLI"
            case "local": return "local bridge"
            case "mcp":   return "MCP"
            default:      return kind
            }
        }
    }

    struct CardType: Decodable, Identifiable {
        var type: String = ""
        var purpose: String = ""
        /// A human-readable contract, e.g. "time:string, date:string". Prose
        /// from the catalog, NOT a list -- it is shown, never parsed.
        var dataFields: String = ""
        /// builtin | forged | scaffold
        var state: String = ""

        var id: String { type }

        private enum CodingKeys: String, CodingKey {
            case type, purpose, state
            case dataFields = "data_fields"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = (try? c.decode(String.self, forKey: .type)) ?? ""
            purpose = (try? c.decode(String.self, forKey: .purpose)) ?? ""
            dataFields = (try? c.decode(String.self, forKey: .dataFields)) ?? ""
            state = (try? c.decode(String.self, forKey: .state)) ?? ""
        }

        var stateLabel: String {
            switch state {
            case "builtin":  return "built in"
            case "forged":   return "made in this house"
            case "scaffold": return "still being built"
            default:         return state
            }
        }
    }

    /// The three groups the list renders, in order. A state the server invents
    /// later lands in `other` rather than vanishing.
    static let groupOrder = ["active", "setup", "available"]

    func apps(inState state: String) -> [App] {
        apps.filter { $0.state == state }
    }
}

@MainActor
final class AppsSurfaceLoader: ObservableObject {
    @Published private(set) var surface: AppsSurface?
    @Published private(set) var isLoading = false
    /// True when the server answered but has no such route (older Valar).
    @Published private(set) var unavailable = false

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = ServerConfig.shared.url("/apps/surface") else {
            unavailable = true
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                print("[Apps] /apps/surface -> HTTP \(code)")
                unavailable = true
                return
            }
            surface = try JSONDecoder().decode(AppsSurface.self, from: data)
            unavailable = false
        } catch {
            print("[Apps] /apps/surface failed: \(error.localizedDescription)")
            unavailable = true
        }
    }
}
