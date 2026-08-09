//
//  PersonaSurface.swift
//  Hearth
//
//  Read-only mirror of `GET /personas/surface`, plus the ONE write this
//  client makes: `POST /personas/apply`.
//
//  Two fields are editable on the phone -- the system prompt and the colours
//  by state -- and the reason is not caution. Those two are the only fields
//  whose value lives entirely inside the persona file. Every other control on
//  the desktop page points at something on the home machine: a model under
//  models/, a wav in the persona's folder, a tool declared in tools.yaml. A
//  model picker here would list names that resolve on exactly one machine.
//  The server accepts other keys from any client; this one does not send them,
//  deliberately, so the desktop keeps the full form.
//
//  Colours cross the wire as hex. The server owns the conversion to the float
//  triples the file stores, so no client ever meets one.
//
//  Fields decode independently with fallbacks, for the reason AppsSurface
//  learned the hard way: the synthesized conformance fails the WHOLE payload
//  on one type mismatch, and a surface derived server-side from twelve persona
//  files will keep moving.
//

import Foundation

public struct PersonaSurface: Decodable {
    public var personas: [Persona] = []
    public var models: [String] = []
    public var domains: [String] = []
    public var forms: [String] = []

    private enum CodingKeys: String, CodingKey {
        case personas, models, domains, forms
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        personas = (try? c.decode([Persona].self, forKey: .personas)) ?? []
        models = (try? c.decode([String].self, forKey: .models)) ?? []
        domains = (try? c.decode([String].self, forKey: .domains)) ?? []
        forms = (try? c.decode([String].self, forKey: .forms)) ?? []
    }

    /// Who the phone shows. `internal` marks machinery rather than a resident
    /// -- the Wright subagents, the routing orchestrator, and the third-party
    /// cores like Liara that belong to an app rather than to the house. The
    /// desktop reveals them under developer mode; iOS has none, so they are
    /// simply not here, and no edit is ever sent for one.
    public var household: [Persona] {
        personas.filter { !$0.isInternal }
    }

    public struct Persona: Decodable, Identifiable {
        public var key: String = ""
        public var name: String = ""
        public var description: String = ""
        public var classification: String = ""
        public var isInternal: Bool = false
        public var systemPrompt: String = ""
        public var voice: Voice = Voice()
        public var form: String = ""
        public var accent: String = ""
        /// nil when the persona has never had a palette of its own. Do not
        /// render an empty control; offer to seed the house colours.
        public var stateColors: [String: String]?
        public var domains: [String] = []
        public var deny: [String] = []
        public var reasoning: Bool = false
        public var rounds: Int = 0
        public var model: String = ""
        public var temperature: Double = 0
        public var visualizationType: String = ""

        public var id: String { key.isEmpty ? name : key }

        /// A model-rendered persona draws no orb, so its state colours drive
        /// nothing. Gated on the RENDERER, never on the name -- Selene today,
        /// Sage when she lands, and any persona whose config changes.
        ///
        /// An EMPTY type is not a model: a persona with no visualization block
        /// falls back to the orb (PersonaVisualization defaults to
        /// sphereParticle), so its colours do apply and it gets the seed
        /// offer. Treating "unknown" as "model" would hide a working control.
        public var usesModelAsset: Bool { visualizationType == "glb_animated" }

        public var formLabel: String {
            switch form {
            case "non_corporeal": return "Non-corporeal"
            case "humanoid":      return "Humanoid"
            case "quadruped":     return "Quadruped"
            case "custom":        return "Something else"
            default:              return form.isEmpty ? "Not set" : form.capitalized
            }
        }

        private enum CodingKeys: String, CodingKey {
            case key, name, description, classification, voice, form, accent
            case domains, deny, reasoning, rounds, model, temperature
            case isInternal = "internal"
            case systemPrompt = "system_prompt"
            case stateColors = "state_colors"
            case type
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = (try? c.decode(String.self, forKey: .key)) ?? ""
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            description = (try? c.decode(String.self, forKey: .description)) ?? ""
            classification = (try? c.decode(String.self, forKey: .classification)) ?? ""
            isInternal = (try? c.decode(Bool.self, forKey: .isInternal)) ?? false
            systemPrompt = (try? c.decode(String.self, forKey: .systemPrompt)) ?? ""
            voice = (try? c.decode(Voice.self, forKey: .voice)) ?? Voice()
            form = (try? c.decode(String.self, forKey: .form)) ?? ""
            accent = (try? c.decode(String.self, forKey: .accent)) ?? ""
            stateColors = try? c.decode([String: String].self, forKey: .stateColors)
            domains = (try? c.decode([String].self, forKey: .domains)) ?? []
            deny = (try? c.decode([String].self, forKey: .deny)) ?? []
            reasoning = (try? c.decode(Bool.self, forKey: .reasoning)) ?? false
            rounds = (try? c.decode(Int.self, forKey: .rounds)) ?? 0
            model = (try? c.decode(String.self, forKey: .model)) ?? ""
            temperature = (try? c.decode(Double.self, forKey: .temperature)) ?? 0

            // The renderer sits at the TOP LEVEL as `type`, flattened by the
            // server out of the persona's visualization block. Verified
            // against the live surface: Selene is "glb_animated", Sulivan and
            // Mentat "sphere_particle", Liara empty.
            visualizationType = (try? c.decode(String.self, forKey: .type)) ?? ""
        }
    }

    public struct Voice: Decodable {
        public var referenceAudio: String = ""
        public var referenceText: String = ""
        public var voiceDescription: String = ""
        public var folder: String = ""

        private enum CodingKeys: String, CodingKey {
            case folder
            case referenceAudio = "reference_audio"
            case referenceText = "reference_text"
            case voiceDescription = "voice_description"
        }

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            referenceAudio = (try? c.decode(String.self, forKey: .referenceAudio)) ?? ""
            referenceText = (try? c.decode(String.self, forKey: .referenceText)) ?? ""
            voiceDescription = (try? c.decode(String.self, forKey: .voiceDescription)) ?? ""
            folder = (try? c.decode(String.self, forKey: .folder)) ?? ""
        }

        /// The clip's own name; the folder it sits in belongs to another
        /// machine and is never shown as something to open.
        public var clipName: String {
            (referenceAudio as NSString).lastPathComponent
        }
    }

    /// The four the house starts from, and what a persona with no palette is
    /// offered. Same hexes the warm defaults use everywhere else.
    public static let seedColors: [String: String] = [
        "idle": "#E39A5B", "listening": "#FFB84D",
        "thinking": "#D68C50", "speaking": "#C97F45",
    ]

    public static let stateOrder = ["idle", "listening", "thinking", "speaking"]

    public static func whenItAppears(_ state: String) -> String {
        switch state {
        case "idle":      return "waiting"
        case "listening": return "you are speaking"
        case "thinking":  return "working it out"
        case "speaking":  return "answering you"
        default:          return ""
        }
    }
}

// MARK: - Loading and saving

@MainActor
public final class PersonaSurfaceLoader: ObservableObject {
    public init() {}
    @Published public private(set) var surface: PersonaSurface?
    @Published public private(set) var isLoading = false
    @Published public private(set) var unavailable = false
    /// Set while the house is restarting after a successful apply.
    @Published public private(set) var isSaving = false
    @Published public private(set) var saveError: String?
    /// What the last apply actually wrote, so a no-op does not claim a save.
    @Published public private(set) var lastChanged: [String] = []

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = ServerConfig.shared.url("/personas/surface") else {
            unavailable = true
            return
        }
        var request = URLRequest(url: url)
        ServerConfig.shared.authorize(&request)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                print("[Persona] /personas/surface -> HTTP \(code)")
                unavailable = true
                return
            }
            surface = try JSONDecoder().decode(PersonaSurface.self, from: data)
            unavailable = false
        } catch {
            print("[Persona] /personas/surface failed: \(error.localizedDescription)")
            unavailable = true
        }
    }

    /// Write the pending edits and wait for the house to come back.
    ///
    /// `apply` writes the files and then EXITS the process, because
    /// persona.json is read once at startup. The websocket dropping is the
    /// expected shape of a successful save, not a failure, so the only real
    /// error cases are a non-200 or a request that never lands at all.
    public func apply(persona: String, prompt: String?, colors: [String: String]?) async -> Bool {
        guard !isSaving else { return false }
        var edit: [String: Any] = [:]
        if let prompt { edit["system_prompt"] = prompt }
        if let colors { edit["state_colors"] = colors }
        guard !edit.isEmpty,
              let url = ServerConfig.shared.url("/personas/apply")
        else { return false }

        isSaving = true
        saveError = nil
        defer { isSaving = false }

        var request = URLRequest(url: url)
        ServerConfig.shared.authorize(&request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["edits": [persona: edit]]
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                saveError = "The house refused the change (HTTP \(code))."
                return false
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            lastChanged = body["changed"] as? [String] ?? []
            // Nothing needed writing: say so rather than claiming a save.
            guard (body["restarting"] as? Bool) ?? false else { return true }
            await waitForServer()
            await load()
            return true
        } catch {
            // The process exits as part of a successful apply, so a dropped
            // connection here is ambiguous rather than fatal. Wait it out and
            // let the reload decide.
            await waitForServer()
            await load()
            return surface != nil
        }
    }

    /// Poll `/health` until the house answers again. Bounded, so a save that
    /// genuinely killed the server does not spin forever.
    private func waitForServer(timeout: TimeInterval = 90) async {
        guard let url = ServerConfig.shared.url("/health") else { return }
        let deadline = Date().addingTimeInterval(timeout)
        // A moment first: the process has to actually go down before its
        // absence means anything, and an immediate poll hits the old one.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        while Date() < deadline {
            var request = URLRequest(url: url)
            ServerConfig.shared.authorize(&request)
            request.timeoutInterval = 3
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        saveError = "Saved, but the house has not come back yet."
    }
}
