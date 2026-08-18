//
//  ClientProfile.swift
//  Hearth
//
//  Client capability tags. Swift mirror of
//  `hearth-client/src/lib/clientProfile.ts` -- same idea, same names, so the
//  two clients cannot drift on which rows exist where.
//
//  A settings row declares what it NEEDS; a client declares what it HAS. No
//  row ever asks "am I on a phone?", which is the point: macOS becomes one
//  line in the table below and zero changes anywhere else. Branching on
//  platform at each row is how a settings page rots.
//
//  visionOS is a SECOND Apple client, not the iOS one in a headset. It links
//  the same package, so before it was named here `ClientProfile.current` was
//  the literal `.ios` and the settings footer told the headset it was a phone.
//  Which client is running is the one genuine platform fact in this file, so it
//  is answered once, at the table, and never again at a row.
//
//  iOS deliberately holds NOTHING:
//    - files    -- the folders are on the Valar machine. A browser on a phone
//                  would open the wrong device's storage.
//    - window   -- no window to remember.
//    - theme    -- iOS follows the OS: Dynamic Type for size, system dark
//                  mode for appearance. Ember mode stays a non-goal.
//    - devpane  -- desktop-only for now, and a table entry if that changes.
//

import Foundation

public enum ClientCapability: String, CaseIterable {
    /// Can browse the machine's own filesystem.
    case files
    /// Has window geometry worth remembering.
    case window
    /// Themes in-app rather than following the OS.
    case inAppTheme = "inapp-theme"
    /// Shows the developer pane.
    case devPane = "devpane"
    /// Has a three-dimensional stage whose furniture -- the typing bar, and
    /// whatever else accrues -- can be shown or hidden. A flat client has no
    /// stage to furnish, which is why this is a capability rather than a row
    /// that checks for a headset.
    case spatialStage = "spatial-stage"
}

public enum ClientId: String {
    case desktop, ios, visionos, echo, quest
}

public enum ClientProfile {
    /// The one platform check in the module, and it belongs here: this file
    /// exists so that nothing ELSE has to ask.
    public static let current: ClientId = {
        #if os(visionOS)
        return .visionos
        #else
        return .ios
        #endif
    }()

    private static let table: [ClientId: Set<ClientCapability>] = [
        .desktop: [.files, .window, .inAppTheme, .devPane],
        .ios: [],
        // No inAppTheme: visionOS answers `dark` to every appearance query, so
        // an in-app theme switch there would be a control fighting the OS.
        .visionos: [.spatialStage],
        .echo: [],
        .quest: [.inAppTheme]
    ]

    /// Does this client carry the capability a row needs?
    public static func can(_ capability: ClientCapability) -> Bool {
        table[current, default: []].contains(capability)
    }

    public static var label: String {
        switch current {
        case .desktop: return "Hearth desktop"
        case .ios:     return "Hearth iOS"
        case .visionos: return "Hearth Vision"
        case .echo:    return "Echo"
        case .quest:   return "Quest"
        }
    }
}
