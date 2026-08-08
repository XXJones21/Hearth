//
//  HearthApp.swift
//  Hearth
//
//  The iOS entry point. A placeholder until area 1 lands the real one, which
//  hosts HearthMainView directly -- there is no ContentView in the clean
//  project, because the only thing Valinor's did was choose between the main
//  view and a classic transcript behind an @AppStorage flag nothing exposes.
//

import SwiftUI

@main
struct HearthApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
    }
}

/// Replaced in area 1. It exists so the target has something to build against
/// while the project topology is being set up, and so a run proves the scaffold
/// works before any migrated source can be blamed for a failure.
private struct PlaceholderView: View {
    var body: some View {
        Text("Hearth")
            .font(.largeTitle.weight(.semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .foregroundStyle(.white)
            .ignoresSafeArea()
    }
}
