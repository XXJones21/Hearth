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

    /// Mirrors ServerConfig so saving an address or pairing swaps the root view
    /// without a relaunch. ServerConfig is the store of record; this is the
    /// redraw trigger, which is why FirstRunView sets it rather than toggling a
    /// flag of its own.
    ///
    /// PAIRED, not merely configured. A phone is never the machine running the
    /// backend, so it is never exempt from the house's gate -- an address with
    /// no token gets a socket closed with 1008 and an orb that sits at
    /// "connecting" forever. First run owns the screen until both halves exist.
    @State private var ready = ServerConfig.shared.isConfigured && ServerConfig.shared.isPaired

    var body: some Scene {
        WindowGroup {
            Group {
                if ready {
                    HearthMainView(viewModel: viewModel)
                } else {
                    FirstRunView()
                }
            }
            .onOpenURL { handleOpenURL($0) }
            .onReceive(NotificationCenter.default.publisher(for: .hearthServerConfigured)) { _ in
                ready = ServerConfig.shared.isConfigured && ServerConfig.shared.isPaired
                // Only once BOTH halves exist. This notification also fires on
                // the address step, when there is still no token -- dialling
                // then earns a socket closed with 1008 and a reconnect loop
                // running behind the pairing screen the person is still using.
                guard ready else { return }
                // The view model was built before an address existed, so its
                // socket was never dialled. Now there is somewhere to dial and
                // a token to dial it with.
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
