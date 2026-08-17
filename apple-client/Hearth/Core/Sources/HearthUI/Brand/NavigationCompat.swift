//
//  NavigationCompat.swift
//  HearthUI
//
//  One modifier, and it exists because of a single API that does not cross.
//
//  `navigationBarTitleDisplayMode` is iOS and tvOS only; visionOS has no
//  navigation bar to give a display mode to. It appeared ten times across the
//  surfaces when they lived in the iOS app target, which cost nothing there and
//  would have cost ten `#if os(iOS)` blocks here.
//
//  So the guard is written once. Every call site reads
//  `.hearthNavigationTitleInline()` and says what it wants -- an inline title --
//  rather than naming a platform. On visionOS the call is a no-op, which is the
//  honest answer: the title renders in the window chrome and the app does not
//  get a say.
//
//  This is the only compatibility shim in HearthUI, and it should stay that
//  way. A second one is a signal that the surface in question is iOS-shaped and
//  belongs back in the app target.
//

import SwiftUI

public extension View {
    /// Inline navigation title where the platform has a navigation bar.
    ///
    /// No-op on visionOS, where window chrome owns the title.
    @ViewBuilder
    func hearthNavigationTitleInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
