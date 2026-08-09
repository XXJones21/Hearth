//
//  HearthApp.swift
//  Hearth
//
//  The iOS entry point.
//
//  Valinor's ValinorApp carried three things this does not: the visionOS scenes
//  behind `#if os(visionOS)`, which belong to their own target now and land in
//  area 6; a Wearables.configure() call in init, which went with MWDAT; and a
//  ContentView that chose between the main view and a classic transcript behind
//  a flag nothing exposed.
//
//  What it does carry, as of area 4, is the one branch that matters: a phone
//  that has not been told where its house is gets the first-run screen, and
//  everything else gets the real shell.
//

import SwiftUI
import HearthCore

@main
struct HearthApp: App {
    /// Built once for the process. ChatViewModel dials in its initializer, so a
    /// view that constructs its own would open a second socket every time
    /// SwiftUI rebuilt the body.
    @StateObject private var viewModel = ChatViewModel()

    /// Mirrors ServerConfig so saving an address swaps the root view without a
    /// relaunch. ServerConfig is the store of record; this is the redraw
    /// trigger, which is why FirstRunView sets it rather than toggling a flag
    /// of its own.
    @State private var configured = ServerConfig.shared.isConfigured

    var body: some Scene {
        WindowGroup {
            Group {
                if configured {
                    HearthMainView(viewModel: viewModel)
                } else {
                    FirstRunView()
                }
            }
            .onOpenURL { handleOpenURL($0) }
            .onReceive(NotificationCenter.default.publisher(for: .hearthServerConfigured)) { _ in
                configured = ServerConfig.shared.isConfigured
                // The view model was built before an address existed, so its
                // socket was never dialled. Now there is somewhere to dial.
                Task { await viewModel.redial() }
            }
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
        viewModel.handleQuickTalkDeepLink()
    }
}
