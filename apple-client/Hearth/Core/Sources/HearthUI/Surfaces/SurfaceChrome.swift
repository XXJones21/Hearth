//
//  SurfaceChrome.swift
//  HearthUI
//
//  Who draws the frame around a shared surface -- and the answer is the HOST,
//  not the surface.
//
//  THE BUG THIS EXISTS FOR. Every destination view wrapped itself in a
//  `NavigationStack` carrying a "Hearth" back button and a parchment toolbar
//  background. That is exactly right in a phone's push-and-pop stack, and it is
//  wrong inside a RealityKit attachment: a volume has no navigation bar to
//  tint, no presentation for `dismiss` to pop, and visionOS renders the
//  navigation container's own material as a glass slab standing in FRONT of the
//  content. The surfaces were not blank on the headset -- they were behind
//  their own chrome, and the chrome swallowed every pinch aimed at them.
//
//  WHY A SPLIT AND NOT A FORK. The tempting fix is a Vision-shaped copy of each
//  view without the stack. That is a second settings screen, a second persona
//  screen and a second apps screen to keep in step with the first, and they
//  drift inside a month. So the BODY stays one view and the CHROME becomes a
//  choice the host makes: the phone asks for `.navigation` and gets the stack
//  it needs; the volume asks for `.bare` and supplies its own header, which it
//  was already drawing.
//
//  It is a presentation choice rather than a platform check on purpose. Nothing
//  here reads `os(visionOS)`, and a phone that one day shows a surface inside a
//  sheet or a split view can ask for `.bare` too.
//

import SwiftUI
import HearthCore

/// How a shared surface should be framed.
public enum HearthSurfaceChrome: Sendable {
    /// A navigation stack with the house's back button and toolbar. The phone.
    case navigation
    /// Body only. The host draws the header and owns the way out. The volume.
    case bare
}

private struct HearthSurfaceChromeKey: EnvironmentKey {
    static let defaultValue: HearthSurfaceChrome = .navigation
}

private struct HearthSurfaceCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

public extension EnvironmentValues {
    /// Defaults to `.navigation`, so a host that says nothing gets the phone's
    /// behaviour unchanged.
    var hearthSurfaceChrome: HearthSurfaceChrome {
        get { self[HearthSurfaceChromeKey.self] }
        set { self[HearthSurfaceChromeKey.self] = newValue }
    }

    /// The way out, when `dismiss` cannot provide one.
    ///
    /// A surface in an attachment is not presented, so SwiftUI's `dismiss` is a
    /// no-op there -- which is why the volume's back button did nothing. A host
    /// that put the surface on screen itself knows how to take it off again and
    /// passes that closure down here.
    var hearthSurfaceClose: (() -> Void)? {
        get { self[HearthSurfaceCloseKey.self] }
        set { self[HearthSurfaceCloseKey.self] = newValue }
    }
}

/// The frame every house destination wears, drawn or not drawn as the host asks.
public struct HearthSurfaceShell<Content: View, Trailing: View>: View {
    @Environment(\.hearthSurfaceChrome) private var chrome
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hearthSurfaceClose) private var close

    private let content: Content
    private let trailing: Trailing
    /// Whether there is a trailing control at all. Checked rather than inferred
    /// from the type, so `EmptyView` passed deliberately still means "none".
    private let hasTrailing: Bool

    public init(@ViewBuilder content: () -> Content) where Trailing == EmptyView {
        self.content = content()
        self.trailing = EmptyView()
        self.hasTrailing = false
    }

    public init(@ViewBuilder trailing: () -> Trailing,
                @ViewBuilder content: () -> Content) {
        self.content = content()
        self.trailing = trailing()
        self.hasTrailing = true
    }

    @ViewBuilder
    public var body: some View {
        switch chrome {
        case .navigation:
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Hearth") { leave() }
                                .tint(HearthPalette.ember)
                        }
                        if hasTrailing {
                            ToolbarItem(placement: .topBarTrailing) { trailing }
                        }
                    }
                    .toolbarBackground(HearthPalette.parchment, for: .navigationBar)
                    .hearthNavigationTitleInline()
            }
        case .bare:
            // No back button: the host's own header carries the way out, and a
            // second one would be two controls doing one job. Trailing controls
            // are real work -- Apps' card library is reachable nowhere else --
            // so they get a strip rather than being dropped.
            VStack(spacing: 0) {
                if hasTrailing {
                    HStack {
                        Spacer()
                        trailing
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                content
            }
        }
    }

    private func leave() {
        if let close { close() } else { dismiss() }
    }
}
