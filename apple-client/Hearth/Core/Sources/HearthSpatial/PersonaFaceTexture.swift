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

    /// How much of the front hemisphere the face spans. Larger is a smaller
    /// face on a bigger head.
    public var extent: Float = 0.62

    public init?(size: Int = 512, kernelName: String = "face_kernel") {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[PersonaFace] no Metal device -- falling back to the SwiftUI face")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            print("[PersonaFace] makeCommandQueue nil -- falling back to the SwiftUI face")
            return nil
        }
        guard let library = Self.loadLibrary(device: device) else {
            print("[PersonaFace] no Metal library anywhere -- falling back to the SwiftUI face")
            return nil
        }
        guard let function = library.makeFunction(name: kernelName) else {
            print("[PersonaFace] \(kernelName) not in the library (has: \(library.functionNames)) -- falling back")
            return nil
        }
        guard let pipeline = try? device.makeComputePipelineState(function: function) else {
            print("[PersonaFace] makeComputePipelineState threw -- falling back to the SwiftUI face")
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
            print("[PersonaFace] LowLevelTexture(descriptor:) threw -- falling back to the SwiftUI face")
            return nil
        }
        guard let resource = try? TextureResource(from: lowLevelTexture) else {
            print("[PersonaFace] TextureResource(from:) threw -- falling back to the SwiftUI face")
            return nil
        }

        self.commandQueue = queue
        self.pipeline = pipeline
        self.lowLevelTexture = lowLevelTexture
        self.textureResource = resource
        self.size = size
        print("[PersonaFace] ready -- \(size)x\(size) rgba16Float, \(kernelName) bound")
    }

    /// Serialise one pose and redraw. Called once per frame from the rig.
    ///
    /// The colour wash is the same one PersonaFaceView applies, from the same
    /// per-state palette the bead reads: the ink leans toward the active state's
    /// colour so the state is legible in peripheral vision. A face that invented
    /// its own colours would drift from the orb it sits on.
    public func draw(pose: FacePose, palette: PersonaPalette, state: HearthState) {
        let glow = palette.glow(for: state)
        let ink = mix(glow, HearthPalette.Scene.roast, 0.62)
        let glint = mix(HearthPalette.Scene.honey, HearthPalette.Scene.fluff, 0.75)

        var params = FaceParams(
            headWidth: Float(pose.headWidth),
            headHeight: Float(pose.headHeight),
            eyeSize: Float(pose.eyeSize),
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
    private static func loadLibrary(device: MTLDevice) -> MTLLibrary? {
        var candidates: [Bundle] = [Bundle(for: PersonaFaceTexture.self)]

        // A package target built as a resource bundle nests it alongside the
        // binary, named for the package and target.
        if let resourceURL = candidates[0].resourceURL {
            let nested = (try? FileManager.default.contentsOfDirectory(
                at: resourceURL, includingPropertiesForKeys: nil)) ?? []
            candidates += nested
                .filter { $0.pathExtension == "bundle" }
                .compactMap { Bundle(url: $0) }
        }
        candidates.append(.main)

        for bundle in candidates {
            if let library = try? device.makeDefaultLibrary(bundle: bundle) {
                print("[PersonaFace] kernel found in \(bundle.bundleURL.lastPathComponent)")
                return library
            }
        }
        // Last resort: the process-wide default, which is the app's own.
        return device.makeDefaultLibrary()
    }
}
