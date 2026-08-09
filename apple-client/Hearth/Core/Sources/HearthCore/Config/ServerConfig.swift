//
//  ServerConfig.swift
//  Hearth
//
//  Where the house is, and the one type that builds an origin.
//
//  The parser below carries across from Valinor unchanged, because it was paid
//  for in bugs. What changed is the default: there is none.
//

import Foundation

public final class ServerConfig {
    public static let shared = ServerConfig()

    private let serverHostKey = "hearth.serverHost"
    private let serverPortKey = "hearth.serverPort"
    private let deviceTokenKey = "hearth.deviceToken"

    /// 18700 is Hearth's client gateway, and the port is the whole default.
    ///
    /// NOT 8700. The development machine runs Valinor's stack there, so a
    /// Hearth build defaulting to 8700 does not fail -- it connects, and comes
    /// up wearing someone else's memory, journal and personas. That is a first
    /// run which looks flawless and is the worst outcome available.
    public static let defaultPort = 18700

    /// **There is deliberately no default host.**
    ///
    /// The desktop client defaults to 127.0.0.1 because it supervises its own
    /// backend and the house genuinely is on that machine. A phone supervises
    /// nothing and is never the machine running the backend, so neither
    /// available default is honest: 127.0.0.1 on a phone is the phone, and a
    /// LAN literal is one machine on one home network compiled into a product.
    ///
    /// Unset is therefore a distinct state rather than a missing value, and the
    /// app in that state does not dial. It renders the bundled persona and asks
    /// where the house is. That makes first run correct by construction instead
    /// of correct by a timeout expiring.
    ///
    /// Bonjour discovery is the obvious later refinement and does not need to
    /// exist for this to be right.
    public var serverHost: String? {
        get {
            guard let saved = UserDefaults.standard.string(forKey: serverHostKey),
                  !saved.isEmpty else { return nil }
            return saved
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                UserDefaults.standard.set(trimmed, forKey: serverHostKey)
            } else {
                UserDefaults.standard.removeObject(forKey: serverHostKey)
            }
        }
    }

    public var serverPort: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: serverPortKey)
            return saved > 0 ? saved : Self.defaultPort
        }
        set { UserDefaults.standard.set(newValue, forKey: serverPortKey) }
    }

    /// The device token this phone was given when it paired, or nil.
    ///
    /// A house exempts loopback and requires a token from everything else, so
    /// a phone always needs one -- a phone is never the machine running the
    /// backend. It is stored beside the address rather than in the Keychain
    /// for now, which is a deliberate pre-alpha shortcut and not a decision:
    /// UserDefaults is readable from a backup, and the Keychain is where this
    /// belongs before anyone who is not us installs it.
    public var deviceToken: String? {
        get {
            guard let saved = UserDefaults.standard.string(forKey: deviceTokenKey),
                  !saved.isEmpty else { return nil }
            return saved
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                UserDefaults.standard.set(trimmed, forKey: deviceTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: deviceTokenKey)
            }
        }
    }

    /// True when someone has told this client where the house is. The socket
    /// must not dial while this is false.
    public var isConfigured: Bool { serverHost != nil }

    /// True when this phone has both an address AND a way in. The distinction
    /// matters to first run: knowing where the house is and being allowed
    /// through its door are two different states, and a client that conflates
    /// them shows "connecting" forever instead of "you need to pair".
    public var isPaired: Bool { deviceToken != nil }

    /// What the Connection field shows and accepts: `host` or `host:port`.
    ///
    /// Clearing it clears the host, and that is the change from Valinor, where
    /// clearing restored the build-time default and a stranger's install could
    /// not get away from one person's LAN address.
    public var address: String {
        get {
            guard let host = serverHost else { return "" }
            return serverPort == Self.defaultPort ? host : "\(host):\(serverPort)"
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                serverHost = nil
                serverPort = Self.defaultPort
                NotificationCenter.default.post(name: .hearthServerConfigured, object: nil)
                return
            }
            defer { NotificationCenter.default.post(name: .hearthServerConfigured, object: nil) }
            // Strip a pasted scheme; people paste URLs.
            var value = trimmed
            for scheme in ["ws://", "wss://", "http://", "https://"] where value.hasPrefix(scheme) {
                value = String(value.dropFirst(scheme.count))
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // Rightmost colon only, and only when what follows is a port --
            // an IPv6 literal is full of colons and must not be split.
            if let colon = value.lastIndex(of: ":"),
               let port = Int(value[value.index(after: colon)...]),
               port > 0, port < 65536 {
                serverHost = String(value[..<colon])
                serverPort = port
            } else {
                serverHost = value
                serverPort = Self.defaultPort
            }
        }
    }

    /// nil until configured, so a caller cannot accidentally dial nowhere.
    public var serverURL: String? {
        guard let host = serverHost else { return nil }
        return "ws://\(host):\(serverPort)"
    }

    /// The single origin. Everything the server hands over as a relative path
    /// resolves against this -- persona assets, generated imagery, the house
    /// surfaces. Exactly one type constructs an origin and no port literal
    /// appears anywhere else in the source; if some asset class is not reachable
    /// through the gateway that is a server bug to file, not a second port for
    /// the client to learn.
    public var httpOrigin: String? {
        guard let host = serverHost else { return nil }
        return "http://\(host):\(serverPort)"
    }

    /// Build a URL against the single origin, or nil when no house is
    /// configured. Every HTTP call in the client goes through this.
    ///
    /// It exists so the rule can be checked by grep rather than by reading:
    /// exactly one type constructs an origin, and no port literal appears
    /// anywhere else in the source. `PersonaStore` in Valinor hardcoded :8766
    /// for persona JSON and fired one request per persona at a port nothing
    /// answered on, hanging until a 60 second timeout -- dead for two months
    /// behind a second bug in the decode. `LocalModelManager` still carries the
    /// same literal today.
    ///
    /// Returning nil rather than a URL against an empty host is the other half
    /// of the no-default-host decision: a surface that cannot build its URL
    /// reports itself unavailable, which is honest, instead of dialling nowhere
    /// and waiting out a timeout.
    public func url(_ path: String) -> URL? {
        guard let origin = httpOrigin else { return nil }
        return URL(string: origin + path)
    }

    /// A request against the house, carrying the device token.
    ///
    /// Every HTTP call in the client goes through this rather than building a
    /// URLRequest of its own, for the same reason every URL goes through
    /// `url(_:)`: so "does this carry credentials" is answered by grep instead
    /// of by auditing each call site. A site that forgets the header does not
    /// fail loudly -- it gets a 401 and reports the house unreachable, which
    /// looks exactly like a network problem.
    public func request(_ path: String, timeout: TimeInterval = 8) -> URLRequest? {
        guard let url = url(path) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        authorize(&request)
        return request
    }

    /// Attach the token, if there is one. Separate so the WebSocket handshake
    /// can use it too -- URLSessionWebSocketTask takes a URLRequest, which is
    /// the only reason a header is possible there at all.
    public func authorize(_ request: inout URLRequest) {
        guard let token = deviceToken else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    /// An asset URL with the token in the QUERY STRING, for the one case that
    /// cannot send a header: `AsyncImage` takes a URL, not a URLRequest, so a
    /// card's picture and a persona's clip have no other way to authenticate.
    ///
    /// Second choice, and only used where it is the only choice -- a query
    /// string lands in server logs where a header does not. It exists because
    /// the alternative is every image in the client 401ing the moment a house
    /// is reached from off its own machine.
    public func assetURL(_ path: String) -> URL? {
        guard let base = url(path) else { return nil }
        guard let token = deviceToken else { return base }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "token", value: token))
        components?.queryItems = items
        return components?.url ?? base
    }

    private init() {}
}

public extension Notification.Name {
    /// The house address changed -- named, or cleared.
    ///
    /// The root view branches on `isConfigured`, and SwiftUI cannot observe a
    /// UserDefaults-backed singleton on its own. This is the redraw signal, and
    /// it fires on the clear path too: forgetting a house has to send the phone
    /// back to first run as surely as naming one takes it forward.
    static let hearthServerConfigured = Notification.Name("hearth.serverConfigured")
}
