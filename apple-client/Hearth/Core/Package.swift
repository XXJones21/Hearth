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
        // One library to start, not three. Splitting inside a package later is
        // cheap; splitting across packages is not.
        .library(name: "HearthCore", targets: ["HearthCore"]),
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
    ]
)
