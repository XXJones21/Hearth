//
//  KernelLibrary.swift
//  HearthSpatial
//
//  Finding the compiled Metal library, which is harder than it should be and
//  has exactly one right answer per build configuration.
//
//  A .metal file in an SPM target does not land in the app's default library.
//  Depending on how the target is built it ends up in the framework's own
//  bundle, in a nested resource bundle named for the package and target, or --
//  when the sources are compiled straight into the app -- in the app's default
//  library after all. So the search tries all three and says which one won,
//  because "kernel not found" and "kernel found in the wrong place" are the
//  same symptom and a log line is the only thing that separates them.
//
//  Written by PersonaFaceTexture first and lifted here unchanged when the
//  animated textures needed it too. Two callers of one search is a shared
//  function; three would have been an argument about which copy was current.
//

import Foundation
import os
import Metal

enum KernelLibrary {
    private static let log = Logger(subsystem: "com.hearth.spatial", category: "kernels")

    static func load(device: MTLDevice) -> MTLLibrary? {
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
                log.notice("kernels found in \(bundle.bundleURL.lastPathComponent, privacy: .public)")
                return library
            }
        }
        // Last resort: the process-wide default, which is the app's own.
        return device.makeDefaultLibrary()
    }
}
