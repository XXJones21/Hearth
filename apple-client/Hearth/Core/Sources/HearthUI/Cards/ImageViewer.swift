//
//  ImageViewer.swift
//  Hearth
//
//  A drawing, full screen. Tap the card's frame to open it.
//
//  The share sheet carries the IMAGE, not its URL. Sharing the URL would give
//  the operator a link to a host only reachable inside the house -- useless in
//  Messages, and worse than useless in a thread with someone else. `Image`
//  conforms to Transferable, so handing it the loaded image gets Save Image,
//  Copy, AirDrop and the rest for free, and they all work off the phone's
//  network.
//
//  That is also why the picture is fetched here rather than reusing
//  RemoteImage: the viewer needs the decoded image as a VALUE to share, not
//  just something drawn on screen.
//

import SwiftUI
import HearthCore

public struct ImageViewer: View {
    public let src: String
    public let prompt: String
    @Environment(\.dismiss) private var dismiss

    @State private var asset = ImageAsset()
    @State private var failed = false
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var showChrome = true

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = asset.image {
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .offset(offset)
                    .gesture(magnification)
                    .gesture(drag)
                    .onTapGesture(count: 2) { toggleZoom() }
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } }
                    .imageActions(asset, prompt: prompt)
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                    Text("The drawing could not be loaded.")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.white.opacity(0.6))
            } else {
                ProgressView().tint(.white)
            }

            if showChrome { chrome }
        }
        .statusBarHidden(!showChrome)
        .task {
            await asset.load(src: src)
            failed = asset.image == nil
        }
        .overlay(alignment: .bottom) {
            if let result = asset.saveResult {
                ImageActionToast(text: result)
                    .padding(.bottom, 46)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        asset.saveResult = nil
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: asset.saveResult)
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.4), in: Circle())
                }
                Spacer()
                if let image = asset.image {
                    ShareLink(item: image,
                              preview: SharePreview(prompt.isEmpty ? "From the easel" : prompt,
                                                    image: image)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            if !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.45))
            }
        }
        .transition(.opacity)
    }

    // MARK: - Gestures

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { zoom = max(1, committedZoom * $0.magnification) }
            .onEnded { _ in
                committedZoom = zoom
                if zoom <= 1 { reset() }
            }
    }

    /// Panning only means anything once the picture is larger than the screen.
    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                offset = CGSize(width: committedOffset.width + value.translation.width,
                                height: committedOffset.height + value.translation.height)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.22)) {
            if zoom > 1 { reset() } else { zoom = 2.5; committedZoom = 2.5 }
        }
    }

    private func reset() {
        zoom = 1
        committedZoom = 1
        offset = .zero
        committedOffset = .zero
    }

}
