//
//  HearthApp.swift
//  Hearth
//
//  The iOS entry point.
//
//  Area 1 shape. Valinor's ValinorApp carried three things this does not: the
//  visionOS scenes behind `#if os(visionOS)`, which belong to their own target
//  now and land in area 6; a Wearables.configure() call in init, which goes with
//  MWDAT; and a ContentView that chose between the main view and a classic
//  transcript behind a flag nothing exposed. ChatViewModel arrives in area 3 and
//  HearthMainView in area 4; until then this hosts the first-run surface, which
//  is the thing area 1 exists to prove.
//

import SwiftUI
import HearthCore

@main
struct HearthApp: App {
    var body: some Scene {
        WindowGroup {
            FirstRunView()
                .onOpenURL { handleOpenURL($0) }
        }
    }

    /// `hearth://talk` from the QuickTalk widget starts a listening turn.
    ///
    /// In Valinor this had to intercept before forwarding to the Wearables SDK,
    /// which owned `valinor://` for its OAuth callbacks -- one scheme registered
    /// for two purposes. With MWDAT out, the interception disappears with it and
    /// the scheme means one thing.
    private func handleOpenURL(_ url: URL) {
        guard url.scheme == "hearth", url.host == "talk" else { return }
        // Wired to the view model in area 3.
    }
}
