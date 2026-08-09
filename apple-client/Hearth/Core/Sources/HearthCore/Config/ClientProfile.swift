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
}

public enum ClientId: String {
    case desktop, ios, echo, quest
}

public enum ClientProfile {
    public static let current: ClientId = .ios

    private static let table: [ClientId: Set<ClientCapability>] = [
        .desktop: [.files, .window, .inAppTheme, .devPane],
        .ios: [],
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
        case .echo:    return "Echo"
        case .quest:   return "Quest"
        }
    }
}
