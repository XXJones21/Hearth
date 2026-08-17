// swift-tools-version: 6.0
//
//  HearthCore -- the platform-neutral core the three targets share.
//
//  This package is what replaces Valinor's membershipExceptions mechanism.
//  There, five files were shared with the widget extension by listing their
//  paths in the project file, and every new shared type meant another path and
//  a pbxproj diff nobody reads. Here the widgets depend on a product, so
//  sharing a sixth type is a `public` keyword in a Swift diff.
//
//  Three more things follow from it being a package rather than a folder:
//  MWDAT cannot appear here because the package does not depend on it, which is
//  what deletes Compat/WearablesShim.swift by construction rather than porting
//  it; the deployment floors are stated once, below, instead of being restated
//  across build configurations; and `swift build` typechecks the model and
//  protocol layer without a simulator.

import PackageDescription

let package = Package(
    name: "HearthCore",
    // Stated once. iOS 26.0 for reach -- nothing in the iOS source needs 27.
    // visionOS 27.0 because the caustics rig calls 27 APIs and the one headset
    // this runs on is ours.
    platforms: [
        .iOS("26.0"),
        .visionOS("27.0"),
    ],
    products: [
        // Three now, and this is the split the original note anticipated: "one
        // library to start, not three. Splitting inside a package later is
        // cheap; splitting across packages is not." Later arrived with the
        // Vision target, which needs the surfaces the iOS app target was
        // holding privately.
        //
        // The layer is the library. HearthCore is logic; HearthUI is the
        // SwiftUI both platforms render; HearthSpatial is the RealityKit both
        // platforms will render. The app targets hold scenes and nothing else.
        .library(name: "HearthCore", targets: ["HearthCore"]),
        .library(name: "HearthUI", targets: ["HearthUI"]),
        .library(name: "HearthSpatial", targets: ["HearthSpatial"]),
    ],
    // Deliberately empty, and it is a standing policy rather than an accident:
    // dependencies attach to targets, never to the project. Valinor's project
    // references mlx-swift-lm, resolves fourteen transitive pins on every clean
    // checkout, and links it into nothing at all.
    dependencies: [],
    targets: [
        .target(
            name: "HearthCore",
            resources: [
                // Ships inside the bundle so first run renders with nothing
                // listening on any port. The Apple client has never had this.
                .process("Resources/Personas"),
            ],
            swiftSettings: [
                // Swift 5, and this is a correction rather than a default.
                //
                // The architecture article proposes Swift 6 for the shared
                // package "where the code is protocol, models and decoding and
                // the concurrency story is simple", with the app targets left
                // on Swift 5 until the audio path -- an AVAudioEngine tap, a
                // player node and a recogniser callback -- has been audited.
                //
                // That split does not survive contact with the boundary this
                // migration actually drew. ChatViewModel, TTSStreamPlayer,
                // SpeechRecognitionManager and AudioSessionManager all land
                // HERE, because both app targets need them. So Swift 6 mode on
                // this package would apply strict concurrency to precisely the
                // code the article says to leave alone, and area 1 found the
                // first instance immediately: ServerConfig.shared is a static
                // on a non-Sendable class, which is a real finding and also the
                // thin end of a wedge that ends in the audio path.
                //
                // Swift 6 is worth adopting deliberately, on its own branch,
                // against a client that already compiles. Not during the move.
                .swiftLanguageMode(.v5),
            ]
        ),
        // The SwiftUI both platforms render: the card library, the brand and
        // persona chrome, and the surfaces -- settings, persona, apps, journal,
        // timeline, sessions -- which lived in the iOS app target until the
        // Vision target needed them and could not see them.
        //
        // Nothing here is iOS-shaped by construction. The one visionOS-hostile
        // modifier in the set, navigationBarTitleDisplayMode, is behind
        // `hearthNavigationTitleInline()` in Brand/NavigationCompat.swift.
        .target(
            name: "HearthUI",
            dependencies: ["HearthCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The RealityKit both platforms will render: the persona rig, the face
        // texture, the behavior system, the book and shelf entities, the card
        // orbit layout.
        //
        // Empty until phase 1 fills it, and declared now so the dependency
        // arrows are settled before there is code to argue about. It builds for
        // iOS as well as visionOS deliberately: that build gate is what keeps
        // the later iOS adoption of the RealityKit orb a target change rather
        // than a rewrite.
        .target(
            name: "HearthSpatial",
            dependencies: ["HearthCore", "HearthUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The face director is time-injected -- `now` is an argument, never a
        // clock read inside -- precisely so its playlists, blink tiers and
        // envelopes can be asserted without a simulator running at 60fps.
        // This target is where that pays off, and it is the package's first.
        //
        // The package declares no macOS platform, so `swift test` cannot build
        // it here; tests run against a simulator, which is what the Makefile
        // target and the plan's xcodebuild invocation both use.
        .testTarget(
            name: "HearthCoreTests",
            dependencies: ["HearthCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
