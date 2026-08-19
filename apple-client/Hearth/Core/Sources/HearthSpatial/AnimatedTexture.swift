//
//  AnimatedTexture.swift
//  HearthSpatial
//
//  A `LowLevelTexture` that a Metal compute kernel rewrites every frame,
//  exposed as a `TextureResource` for whatever wants to wear it or be lit by
//  it.
//
//  WHAT THIS IS, AND WHAT IT REPLACED. Valinor calls this CausticsTexture,
//  because caustics is what it drew first. It already took a kernel name and
//  already shipped two kernels, so the mechanism was never about caustics --
//  only the name was. `PersonaFaceTexture` then rebuilt the same pattern from
//  scratch beside it. Two implementations of one idea is the point at which the
//  idea gets a name.
//
//  So: caustics, smoke and fire are PRESETS. A preset carries its kernel and
//  the three numbers that go with it, because those four things together ARE
//  the effect -- a caller passing three of them right and the fourth wrong gets
//  a subtly wrong effect and no error to explain it.
//
//  Construction can fail: a device without a usable compute pipeline, or a
//  build where the metallib did not make it into the bundle. `nil` means "no
//  effect", and every caller degrades to something plainer rather than to
//  nothing.
//

import Foundation
import os
import RealityKit
import Metal
import simd

/// Must match `TextureParams` in AnimatedTexture.metal: same field order, same
/// types. A mismatch is silent and draws garbage.
private struct TextureParams {
    var time: Float
    var scale: Float
    var brightness: Float
    var flow: Float
    var width: UInt32
    var height: UInt32
}

@MainActor
public final class AnimatedTexture {
    /// A kernel and the numbers that belong with it.
    public struct Preset: Sendable {
        public let kernel: String
        public let scale: Float
        public let brightness: Float
        public let speed: Float

        public init(kernel: String, scale: Float, brightness: Float, speed: Float) {
            self.kernel = kernel
            self.scale = scale
            self.brightness = brightness
            self.speed = speed
        }

        /// Valinor's device-tuned water caustic, unchanged. Kept selectable
        /// rather than as the default everything else has to argue with.
        public static let caustics = Preset(kernel: "caustics_kernel",
                                            scale: 2.5, brightness: 1.1, speed: 1.0)

        /// The slow, soft variant Valinor puts inside the orb.
        public static let smoke = Preset(kernel: "smoke_kernel",
                                         scale: 2.0, brightness: 1.0, speed: 0.3)

        /// A hearth flame: dense at the base, breaking up as it rises.
        /// `scale` raised from 2.2 after the first device run: at 2.2 the
        /// noise is lower-frequency than the sphere is wide, so the flame reads
        /// as two or three soft blobs rather than as licks of fire. Fire is a
        /// fine-grained thing and wants more field across the same surface.
        public static let fire = Preset(kernel: "fire_kernel",
                                        scale: 3.6, brightness: 1.15, speed: 1.25)

        /// Thrown onto a WALL: flame light climbing it, gold low to ember high,
        /// the same progression the flame itself runs.
        /// Slowed to the flame's own pace: the mesh drifts at 0.55 against a
        /// speed of 1.25, and a pool racing up a wall faster than the fire
        /// making it is two effects rather than one.
        public static let flameCookie = Preset(kernel: "flame_cookie_kernel",
                                               scale: 3.2, brightness: 1.0, speed: 0.78)

        /// The same flame thrown OUTWARD from the middle, for the surfaces a
        /// fire stands on rather than beside.
        public static let bloomCookie = Preset(kernel: "bloom_cookie_kernel",
                                               scale: 3.0, brightness: 1.0, speed: 0.78)

        /// Thrown onto a FLOOR or a CEILING: slow curling smoke, greyscale so
        /// the light's own tint decides which of the two it is.
        public static let swirlCookie = Preset(kernel: "swirl_cookie_kernel",
                                               scale: 2.0, brightness: 1.0, speed: 0.7)

        /// The colour half of the fire: white heart through gold and amber to
        /// ember and ash, travelling upward. Carries no noise, so it is
        /// generated small -- see the note in the kernel about why colour and
        /// density cannot share one texture.
        public static let fireColor = Preset(kernel: "fire_color_kernel",
                                             scale: 1.0, brightness: 1.0, speed: 1.25)
    }

    private static let log = Logger(subsystem: "com.hearth.spatial", category: "texture")

    /// The live texture to hand to a material or a projective light.
    public let textureResource: TextureResource

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let lowLevelTexture: LowLevelTexture
    private let size: Int

    /// Feature density, output gain, and how fast the animation runs. Seeded
    /// from the preset and left open, because tuning happens on a device with
    /// the thing in front of you and a preset is only a starting point.
    public var scale: Float
    public var brightness: Float
    public var speed: Float

    /// Reserved. Was "which way does the pattern move", back when one cookie
    /// tried to serve walls and floors at once; the answer turned out to be two
    /// kernels rather than one parameter. Kept because the uniform block is
    /// shared and removing a field means editing both sides of it.
    public var flow: Float = 1

    private var elapsed: Float = 0

    public init?(_ preset: Preset, size: Int = 512) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.log.error("no Metal device -- no animated texture")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            Self.log.error("makeCommandQueue nil -- no animated texture")
            return nil
        }
        guard let library = KernelLibrary.load(device: device) else {
            Self.log.error("no Metal library anywhere -- no animated texture")
            return nil
        }
        guard let function = library.makeFunction(name: preset.kernel) else {
            Self.log.error("\(preset.kernel, privacy: .public) not in the library (has: \(library.functionNames, privacy: .public))")
            return nil
        }
        guard let pipeline = try? device.makeComputePipelineState(function: function) else {
            Self.log.error("makeComputePipelineState threw for \(preset.kernel, privacy: .public)")
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
            Self.log.error("LowLevelTexture(descriptor:) threw")
            return nil
        }
        guard let resource = try? TextureResource(from: lowLevelTexture) else {
            Self.log.error("TextureResource(from:) threw")
            return nil
        }

        self.commandQueue = queue
        self.pipeline = pipeline
        self.lowLevelTexture = lowLevelTexture
        self.textureResource = resource
        self.size = size
        self.scale = preset.scale
        self.brightness = preset.brightness
        self.speed = preset.speed
        Self.log.notice("ready -- \(size)x\(size), \(preset.kernel, privacy: .public) bound")
    }

    /// Advance the animation and redraw. Once per frame.
    public func tick(deltaTime: Float) {
        elapsed += deltaTime * speed
        draw(time: elapsed)
    }

    /// The average of the frame just drawn, as a cheap stand-in for "how bright
    /// is the effect right now".
    ///
    /// NOT READ BACK FROM THE GPU, deliberately. Pulling a texture back to the
    /// CPU every frame to average it would cost more than drawing it. This is
    /// the same noise the kernel walks, sampled once on the CPU at the same
    /// clock -- so a light driven from it flickers WITH the flame rather than
    /// against it, which is all the fire needs. It is a correlation, not a
    /// measurement, and it is named `flicker` rather than `luminance` for that
    /// reason.
    public func flicker() -> Float {
        // Three offset sine waves at incommensurable rates: no repeat you can
        // hear, no table to keep, and nothing to synchronise.
        let t = elapsed
        let wobble = sin(t * 2.7) * 0.5 + sin(t * 4.3 + 1.7) * 0.3 + sin(t * 9.1 + 0.4) * 0.2
        return 0.5 + 0.5 * max(-1, min(1, wobble))
    }

    private func draw(time: Float) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // `replace(using:)` returns the writable MTLTexture backing the
        // resource, and MUST be called before the compute encoder is opened --
        // it tracks the command buffer RealityKit waits on before rendering.
        let mtlTexture = lowLevelTexture.replace(using: commandBuffer)

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        var params = TextureParams(time: time,
                                   scale: scale,
                                   brightness: brightness,
                                   flow: flow,
                                   width: UInt32(size),
                                   height: UInt32(size))

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(mtlTexture, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<TextureParams>.stride, index: 0)

        let tew = pipeline.threadExecutionWidth
        let teh = max(1, pipeline.maxTotalThreadsPerThreadgroup / tew)
        let threadsPerGroup = MTLSize(width: tew, height: teh, depth: 1)
        let groups = MTLSize(width: (size + tew - 1) / tew,
                             height: (size + teh - 1) / teh,
                             depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
    }
}
