//
//  ImageCard.swift
//  Hearth
//
//  A picture from the local art studio, shown from the moment it is asked for.
//
//  The card lands in the timeline while the canvas is still blank and settles
//  in place. It ALWAYS arrives `status: "running"` with an empty `src`,
//  because the server emits it at submit time, before the render exists --
//  which is why the running state is the one worth building first. The old
//  flow put nothing on screen at all unless the operator asked a second time
//  and the model happened to choose `check_image`, so a turn could end with
//  "it should be ready" and leave the transcript empty.
//
//  The outcome is read from EaselStore rather than held here; see that file
//  for why a LazyVStack makes per-card state the wrong place for it.
//

import SwiftUI

struct ImageCard: View {
    let descriptor: UiComponentDescriptor
    @ObservedObject private var easel = EaselStore.shared

    /// The frame's height is fixed rather than derived from an aspect ratio,
    /// and is IDENTICAL in both states, so the feed does not jump when the
    /// picture arrives. 3:2 landscape at the card's usable width.
    private let frameHeight: CGFloat = 208

    @State private var showViewer = false
    @State private var asset = ImageAsset()

    private var jobID: String { descriptor.str("job_id") }
    private var prompt: String { descriptor.str("prompt") }

    /// The store wins when it holds this job, the props otherwise. Falling
    /// back to props is what makes a card survive being rebuilt after a
    /// scroll, and what makes a card from an earlier session render at all.
    private var live: EaselStore.Outcome {
        if let outcome = easel.outcome(for: jobID) { return outcome }
        return EaselStore.Outcome(
            status: descriptor.str("status", fallback: "done"),
            src: descriptor.str("src"),
            note: descriptor.str("note")
        )
    }

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 9) {
                header
                if live.status == "error" {
                    errorBody
                } else {
                    frame
                }
                // The prompt in BOTH states: it is what makes a card with no
                // picture in it worth looking at. Flux prompts come back long,
                // so it wraps rather than truncating.
                if !prompt.isEmpty {
                    Text(prompt)
                        .font(.system(size: 11.5))
                        .foregroundStyle(HearthPalette.fawn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { easel.watch(jobID: jobID) }
        .onDisappear { easel.stop() }
        .fullScreenCover(isPresented: $showViewer) {
            ImageViewer(src: live.src, prompt: prompt)
        }
        .overlay(alignment: .bottom) {
            if let result = asset.saveResult {
                ImageActionToast(text: result)
                    .padding(.bottom, 14)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        asset.saveResult = nil
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: asset.saveResult)
    }

    private var header: some View {
        HStack(spacing: 8) {
            CardEyebrow(text: descriptor.str("title", fallback: "From the easel"))
            if live.status == "running" {
                HStack(spacing: 5) {
                    PulsingDot()
                    Text("drawing")
                        .font(.system(size: 11))
                        .foregroundStyle(HearthPalette.fawn)
                }
            }
        }
    }

    @ViewBuilder
    private var frame: some View {
        if live.src.isEmpty {
            // Deliberately NOT RemoteImage: its loading state is a
            // ProgressView, which is right for a fetch and wrong here. There
            // is nothing to fetch yet, and nothing about a Flux render is
            // measurable, so a bar or a spinner would be inventing a number.
            BlankCanvas()
                .frame(height: frameHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            // `src` arrives WITHOUT a leading slash ("assets/generated/...").
            // hearthAssetURL adds one and resolves against the Valar origin,
            // so the card keeps working when the phone is on tailscale rather
            // than the LAN. Never hand-build this URL.
            RemoteImage(src: live.src, height: frameHeight)
                .contentShape(Rectangle())
                .onTapGesture { showViewer = true }
                .imageActions(asset, prompt: prompt)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(prompt.isEmpty ? "Open the drawing" : "Open the drawing: \(prompt)")
                // Loaded for the menu, not for the frame: ShareLink needs its
                // item at construction, and URLCache already holds the bytes.
                .task(id: live.src) { await asset.load(src: live.src) }
        }
    }

    private var errorBody: some View {
        Text(live.note.isEmpty ? "The drawing did not finish." : live.note)
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .foregroundStyle(HearthPalette.clay)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(HearthPalette.clayWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HearthPalette.clayLine, lineWidth: 1)
            )
    }
}

/// The blank canvas: a slow warm sweep across parchment. It reads as "being
/// worked on" without claiming to know how far along it is.
private struct BlankCanvas: View {
    @State private var shift: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            HearthPalette.parchment
                .overlay(
                    LinearGradient(
                        colors: [HearthPalette.parchment.opacity(0),
                                 HearthPalette.glowtint,
                                 HearthPalette.parchment.opacity(0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: shift * geo.size.width)
                )
                .clipped()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: false)) {
                shift = 1.4
            }
        }
    }
}

private struct PulsingDot: View {
    @State private var faded = false

    var body: some View {
        Circle()
            .fill(HearthPalette.honey)
            .frame(width: 6, height: 6)
            .opacity(faded ? 0.25 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    faded = true
                }
            }
    }
}
