//
//  BundledPersona.swift
//  Hearth
//
//  The persona that ships inside the app, so first run renders before any
//  backend exists.
//
//  NET NEW. Valinor's Apple client has never had this: it asks the server with
//  `get_persona_config` and falls back to warm constants written in Swift, so a
//  phone with nothing to talk to shows a palette-default orb rather than
//  Sulivan. The desktop client solved it years earlier by importing
//  src/personas/sulivan.json directly, which is what makes ITS first run
//  standalone.
//
//  The file is the same JSON the server serves, and it is decoded by the same
//  `PersonaPalette.from(visualization:)` that handles the wire payload. That is
//  the point: the warm constants stop being a second copy of the numbers in
//  sulivan.json written in a different language and free to drift.
//

import Foundation

public struct BundledPersona: Sendable {
    public let name: String
    public let visualizationJSON: Data

    /// Sulivan, from `Resources/Personas/sulivan.json` inside the package.
    ///
    /// nil only if the resource is missing from the bundle, which is a build
    /// error rather than a runtime condition -- but it is returned rather than
    /// trapped, because a crash on first launch is a worse way to learn it.
    public static let sulivan: BundledPersona? = load(named: "sulivan")

    /// The `visualization` block, in the shape the wire payload uses.
    public var visualization: [String: Any]? {
        let object = try? JSONSerialization.jsonObject(with: visualizationJSON)
        return (object as? [String: Any])?["visualization"] as? [String: Any]
    }

    private static func load(named name: String) -> BundledPersona? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let object = try? JSONSerialization.jsonObject(with: data)
        let displayName = (object as? [String: Any])?["name"] as? String
        return BundledPersona(name: displayName ?? name.capitalized, visualizationJSON: data)
    }
}
