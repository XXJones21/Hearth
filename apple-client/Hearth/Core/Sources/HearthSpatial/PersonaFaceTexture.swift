//
//  PersonaFaceTexture.swift
//  HearthSpatial
//
//  A `LowLevelTexture` that `face_kernel` rewrites every frame, exposed as a
//  `TextureResource` for the orb's face shell to wear.
//
//  Structurally a sibling of Valinor's CausticsTexture, and deliberately so:
//  same construction, same fallible init, same replace-then-encode ordering.
//  That code was never validated on a device, which is why the design calls the
//  pattern unproven and puts its first real proof here. If the pattern is wrong,
//  it is wrong in one small file with a working fallback behind it rather than
//  in the middle of the caustics rig.
//
//  DIVISION OF LABOUR. FaceDirector decides everything about WHEN -- playlists,
//  blink schedules, saccades, transient envelopes, the amplitude mouth -- and is
//  reused with zero changes, exactly as the design asks. This file only
//  serialises the pose it returns and dispatches the draw. There is no second
//  state machine here and there must never be one: the phone and the headset
//  disagreeing about when Sulivan blinks would be a bug nobody could name.
//
//  WHY IT CAN RETURN NIL. A device without a usable compute pipeline, or a
//  build where the metallib did not make it into the bundle, gets `nil` -- and
//  the rig mounts the SwiftUI PersonaFaceView as a billboard attachment
//  instead. Degraded, never faceless.
//

import Foundation
import os
import RealityKit
import Metal
import simd
import HearthCore

/// Must match `FaceParams` in FaceKernel.metal: same field order, same types,
/// same padding. A mismatch is silent and draws garbage.
///
/// `float3` in Metal is 16-byte aligned, so the two colour fields sit on
/// 16-byte boundaries here too. That is what SIMD3<Float> already does in
/// Swift, which is why this is a plain struct and not a hand-packed buffer.
private struct FaceParams {
    // Pose -- geometry
    var headWidth: Float
    var headHeight: Float
    var eyeSize: Float
    var eyeSpacing: Float
    var eyeHeight: Float
    var eyeLength: Float
    var eyeTilt: Float
    var mouthWidth: Float
    var mouthThickness: Float
    var mouthCurve: Float
    // Pose -- motion
    var eyelidL: Float
    var eyelidR: Float
    var eyeArc: Float
    var focus: Float
    var eyeScaleL: Float
    var eyeScaleR: Float
    var eyeTiltL: Float
    var eyeTiltR: Float
    var eyeRaiseL: Float
    var eyeRaiseR: Float
    var gazeX: Float
    var gazeY: Float
    var mouthOpen: Float
    var mouthRound: Float
    // Colours
    var ink: SIMD3<Float>
    var glint: SIMD3<Float>
    var iris: SIMD3<Float>
    var irisAmount: Float
    var eyeStyle: Float
    // Projection
    var lonOffset: Float
    var extent: Float
    var width: UInt32
    var height: UInt32
}

@MainActor
public final class PersonaFaceTexture {
    /// The live texture the face shell wears.
    public let textureResource: TextureResource

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let lowLevelTexture: LowLevelTexture
    private let size: Int

    /// Where the front of the sphere falls in u, in radians.
    ///
    /// Exposed rather than baked because it depends on where RealityKit's
    /// sphere generator puts its seam, and that is a detail of a mesh we did
    /// not author. If the face lands on the back or the side of the bead, this
    /// is the one number to turn.
    public var longitudeOffset: Float = 0

    /// How much of the front hemisphere the face spans.
    ///
    /// LARGER IS A BIGGER FACE. A feature drawn at half-width `w` in face space
    /// covers `w * extent` of the sphere's surface, so raising this grows the
    /// eyes rather than shrinking them. (An earlier version of this comment
    /// said the opposite, which was simply wrong.)
    ///
    /// 0.68 is 0.62 stepped up a tenth, on the operator's read of the first
    /// correctly-oriented device run: the face was in the right place and sat a
    /// little small on a bead the size of a palm.
    ///
    /// This scales the WHOLE face and leaves its proportions alone. Making the
    /// eyes bigger *relative* to everything else is `eyeScale`.
    public var extent: Float = 0.68

    /// Multiplier on the persona's own `eyeSize`.
    ///
    /// A TEST KNOB, and the shape of it is the point. The geometry still comes
    /// from the persona file through FaceGeometry, exactly as it does on the
    /// phone -- this only scales what arrives, so the persona stays the source
    /// of truth and nothing here forks it.
    ///
    /// 1.2 is the operator's read against a hand held up beside the orb, which
    /// is the only scale reference that means anything here: eyes tuned for a
    /// flat 130pt phone view are small on a bead you can hold.
    ///
    /// If it survives testing the multiplier should GO, and the number should
    /// move into the persona file where both clients read it. A headset that
    /// permanently multiplies a shared value is a headset quietly drawing a
    /// different Sulivan; a persona whose eyes are simply bigger is Sulivan.
    public var eyeScale: Float = 1.2

    /// How far the ink leans toward `roast` from the state's glow colour.
    ///
    /// The flat renderer's value, deliberately. This was briefly raised to 0.78
    /// to fight a face that came up too bright, which turned out to be a colour
    /// SPACE fault rather than a colour one -- see `linearized`. With the real
    /// cause fixed, the mix goes back to matching the phone, because the two
    /// renderers drawing the same persona in different browns is a drift nobody
    /// would notice until they were side by side.
    ///
    /// Only consulted when `inkStyle` is `.stateWash`.
    public var inkBlend: Float = 0.62

    /// What colour the ink is.
    public enum InkStyle: Sendable {
        /// Flat black, ignoring the persona entirely.
        case flatBlack
        /// The phone's treatment: ink leaning toward `roast` from the active
        /// state's glow colour, so the state is legible in peripheral vision.
        case stateWash
    }

    /// Flat black for now, at the operator's call after seeing the wash on the
    /// device.
    ///
    /// Worth being honest that this is a step AWAY from the design: section 3
    /// has the face reading its colours from the same per-state palette the
    /// bead does, so a face never invents colours the orb does not have. On a
    /// bright emissive bead the washed brown reads as smudged rather than
    /// drawn, and flat black simply reads.
    ///
    /// Kept as a switch rather than a deletion because the wash is not wrong in
    /// principle -- it is what makes the state legible from across a room, and
    /// it may come back once the bead is not the only thing behind it. Revisit
    /// with the phase 5 polish pass.
    public var inkStyle: InkStyle = .flatBlack

    /// The eye's colour inside the ink rim, and how much of it to show.
    ///
    /// A TEST, 2026-08-19: the flame turned out warm enough that a cool iris
    /// reads as a real composition rather than a decoration, and the reference
    /// is Charmander's blue against its own fire. Nothing about the eye's shape
    /// or its glint changes -- the iris is the same silhouette eroded inward,
    /// so it blinks and tilts and narrows with the eye it lives in.
    ///
    /// `irisAmount` at zero draws none, which is what every persona that has
    /// not asked for one gets. It is a knob rather than a constant because the
    /// eventual home for this is the persona config beside `eye_size` and the
    /// rest of `FaceGeometry` -- a persona should be able to have blue eyes
    /// without a client build.
    /// Charmander's cyan-blue, read off the reference rather than guessed at:
    /// vivid rather than pastel, which is what holds its own against a fire.
    /// The kernel darkens it toward the top of the eye and lifts it toward the
    /// bottom, so this one value becomes the whole gradient.
    public var irisColor = SIMD3<Float>(0.16, 0.62, 0.88)
    public var irisAmount: Float = 0

    /// Which eye the kernel draws.
    ///
    /// `ink` is the shipped one: a dark capsule with a glint, a mark ON a face,
    /// letting the persona's own surface show around it. `chibi` is an eye IN a
    /// face -- a white oval, a coloured iris, a dark pupil, a heavy lash line
    /// and two unequal highlights.
    ///
    /// A VARIANT AND NOT A REPLACEMENT, on the operator's instruction: the ink
    /// eye is device-tested and correct for the bead, and this exists to be
    /// looked at on a flame. It changes the eye's SHAPE, so anything measured
    /// against the old silhouette is expected to want re-tuning.
    public enum EyeStyle: Sendable { case ink, chibi }
    public var eyeStyle: EyeStyle = .ink

    public init?(size: Int = 512, kernelName: String = "face_kernel") {
        guard let device = MTLCreateSystemDefaultDevice() else {
            log.error("no Metal device -- falling back to the SwiftUI face")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            log.error("makeCommandQueue nil -- falling back to the SwiftUI face")
            return nil
        }
        guard let library = Self.loadLibrary(device: device) else {
            log.error("no Metal library anywhere -- falling back to the SwiftUI face")
            return nil
        }
        guard let function = library.makeFunction(name: kernelName) else {
            log.error("\(kernelName, privacy: .public) not in the library (has: \(library.functionNames, privacy: .public)) -- falling back")
            return nil
        }
        guard let pipeline = try? device.makeComputePipelineState(function: function) else {
            log.error("makeComputePipelineState threw -- falling back to the SwiftUI face")
            return nil
        }

        var descriptor = LowLevelTexture.Descriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = size
        descriptor.height = size
        descriptor.mipmapLevelCount = 1
        descriptor.textureUsage = [.shaderRead, .shaderWrite]

        guard let lowLevelTexture = try? LowLevelTexture(descriptor: descriptor) else {
            log.error("LowLevelTexture(descriptor:) threw -- falling back to the SwiftUI face")
            return nil
        }
        guard let resource = try? TextureResource(from: lowLevelTexture) else {
            log.error("TextureResource(from:) threw -- falling back to the SwiftUI face")
            return nil
        }

        self.commandQueue = queue
        self.pipeline = pipeline
        self.lowLevelTexture = lowLevelTexture
        self.textureResource = resource
        self.size = size
        log.notice("ready -- \(size)x\(size) rgba16Float, \(kernelName, privacy: .public) bound")
    }

    /// Serialise one pose and redraw. Called once per frame from the rig.
    ///
    /// The colour wash is the same one PersonaFaceView applies, from the same
    /// per-state palette the bead reads: the ink leans toward the active state's
    /// colour so the state is legible in peripheral vision. A face that invented
    /// its own colours would drift from the orb it sits on.
    public func draw(pose: FacePose, palette: PersonaPalette, state: HearthState) {
        let ink: SIMD3<Float>
        switch inkStyle {
        case .flatBlack:
            // Already linear. Black is black in either space, so this one does
            // not go through `linearized` -- and saying so is cheaper than
            // leaving a reader to wonder why it does not.
            ink = .zero
        case .stateWash:
            ink = linearized(mix(palette.glow(for: state), HearthPalette.Scene.roast, inkBlend))
        }
        let glint = linearized(mix(HearthPalette.Scene.honey, HearthPalette.Scene.fluff, 0.75))

        var params = FaceParams(
            headWidth: Float(pose.headWidth),
            headHeight: Float(pose.headHeight),
            // The one pose channel that is not passed through verbatim. See
            // `eyeScale`: the persona still owns the value, this only scales it
            // while the right number is being found.
            eyeSize: Float(pose.eyeSize) * eyeScale,
            eyeSpacing: Float(pose.eyeSpacing),
            eyeHeight: Float(pose.eyeHeight),
            eyeLength: Float(pose.eyeLength),
            eyeTilt: Float(pose.eyeTilt),
            mouthWidth: Float(pose.mouthWidth),
            mouthThickness: Float(pose.mouthThickness),
            mouthCurve: Float(pose.mouthCurve),
            eyelidL: Float(pose.eyelidL),
            eyelidR: Float(pose.eyelidR),
            eyeArc: Float(pose.eyeArc),
            focus: Float(pose.focus),
            eyeScaleL: Float(pose.eyeScaleL),
            eyeScaleR: Float(pose.eyeScaleR),
            eyeTiltL: Float(pose.eyeTiltL),
            eyeTiltR: Float(pose.eyeTiltR),
            eyeRaiseL: Float(pose.eyeRaiseL),
            eyeRaiseR: Float(pose.eyeRaiseR),
            gazeX: Float(pose.gazeX),
            gazeY: Float(pose.gazeY),
            mouthOpen: Float(pose.mouthOpen),
            mouthRound: Float(pose.mouthRound),
            ink: ink,
            glint: glint,
            iris: irisColor,
            irisAmount: irisAmount,
            eyeStyle: eyeStyle == .chibi ? 1 : 0,
            lonOffset: longitudeOffset,
            extent: extent,
            width: UInt32(size),
            height: UInt32(size))

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // `replace(using:)` MUST be called before the encoder is opened: it
        // returns the writable MTLTexture and registers the command buffer that
        // RealityKit waits on before it renders the texture. Opening the
        // encoder first races the renderer.
        let mtlTexture = lowLevelTexture.replace(using: commandBuffer)

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(mtlTexture, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<FaceParams>.stride, index: 0)

        let tew = pipeline.threadExecutionWidth
        let teh = max(1, pipeline.maxTotalThreadsPerThreadgroup / tew)
        encoder.dispatchThreadgroups(
            MTLSize(width: (size + tew - 1) / tew, height: (size + teh - 1) / teh, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tew, height: teh, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a * (1 - t) + b * t
    }

    /// sRGB components to linear.
    ///
    /// This is the difference between the face and the bead, and it is why the
    /// first two device runs came up too bright.
    ///
    /// HearthPalette.Scene stores components as hex/255, which is the sRGB
    /// convention -- the file says so. The bead hands those to RealityKit
    /// through UIColor(red:green:blue:), which declares them sRGB, and the
    /// renderer converts. The face writes them into an rgba16Float texture, and
    /// a float texture is LINEAR: whatever is in it is taken at face value. So
    /// the same numbers that make the bead correct made the ink roughly
    /// pow(c, 1/2.2) too light, which is most of a stop.
    ///
    /// `roast` is the clearest case: 0.231 as an sRGB component is 0.045 in
    /// linear, and the difference between those two is exactly the difference
    /// between ink and a smudge.
    private func linearized(_ c: SIMD3<Float>) -> SIMD3<Float> {
        func channel(_ v: Float) -> Float {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return SIMD3<Float>(channel(c.x), channel(c.y), channel(c.z))
    }

    /// Find the compiled kernel, wherever the build put it.
    ///
    /// This is the one real difference from Valinor, where the kernel sat in
    /// the app target and `makeDefaultLibrary()` simply found it. Here it ships
    /// inside a package target: the build compiles FaceKernel.metal, links a
    /// `default.metallib`, and copies it into `HearthCore_HearthSpatial.bundle`
    /// -- nested inside the app rather than at its root, which is exactly what
    /// `makeDefaultLibrary()` alone will not find.
    ///
    /// `Bundle.module` would in fact work: the build does synthesise the
    /// accessor, because a compiled metallib counts as a resource. This searches
    /// anyway, and the reason is the fallback rather than doubt -- `Bundle.module`
    /// traps at runtime when the bundle is missing, which would turn "no face"
    /// into "no app" on precisely the build where the graceful `nil` matters
    /// most. `Bundle(for:)` cannot trap, and the nested scan below finds the
    /// same bundle whether the target links statically into the app or ships as
    /// its own framework.
    /// See `KernelLibrary`, which is this search after the animated textures
    /// needed the same one.
    private static func loadLibrary(device: MTLDevice) -> MTLLibrary? {
        KernelLibrary.load(device: device)
    }
}
