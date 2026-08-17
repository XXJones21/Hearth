//
//  RemoteImage.swift
//  Hearth
//
//  The one image loader the dynamic cards share. Until this existed, both
//  `generated_view`'s image sections and `slideshow` rendered their `src` as
//  grey placeholder TEXT -- the path, not the picture.
//
//  Resolution follows the same rule as every other Valar asset (see
//  PersonaVisualization.clipURL): an absolute URL is taken as given, and
//  anything else resolves against the Valar origin. The server emits
//  house-relative paths like "/assets/kiln.png" because it has no idea which
//  interface a client reached it on -- a phone on tailscale and a desktop on
//  the LAN see different hosts for the same file.
//
//  Caching is URLSession's: AsyncImage goes through the shared URLCache, which
//  already holds a disk store. A slideshow cycling four images should hit the
//  network once each, not once per revolution.
//

import SwiftUI
import HearthCore

/// Absolute URL for a card's `src`, or nil when it cannot be resolved.
///
/// Kept separate from the view so the slideshow can resolve a whole list up
/// front and drop what it cannot load, rather than discovering it mid-cycle.
func hearthAssetURL(_ src: String) -> URL? {
    let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Already absolute: a card may legitimately point at something outside
    // the house, and rewriting that would break it.
    if let url = URL(string: trimmed), url.scheme != nil {
        return url
    }

    // No house configured means no relative asset can resolve. nil is the
    // honest answer and the card already renders it as a failed image.
    let path = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    guard let encoded = path.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed.union(CharacterSet(charactersIn: "?&=#"))
    ) else { return nil }
    return ServerConfig.shared.assetURL(encoded)
}

/// A card image: resolved, loaded, and honest when it fails.
///
/// A broken asset shows a marked frame rather than collapsing to nothing. In
/// the timeline a missing card should be silent (forward compatibility), but a
/// card that DID render and whose picture failed is a different thing -- going
/// blank there would read as "the persona sent an empty card".
public struct RemoteImage: View {
    public let src: String
    public var height: CGFloat = 160
    public var cornerRadius: CGFloat = 12

    public var body: some View {
        Group {
            if let url = hearthAssetURL(src) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.18))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        failed
                    case .empty:
                        loading
                    @unknown default:
                        loading
                    }
                }
            } else {
                failed
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(HearthPalette.bubbleLine, lineWidth: 1)
        )
    }

    private var loading: some View {
        HearthPalette.parchment
            .overlay(ProgressView().tint(HearthPalette.fawn))
    }

    private var failed: some View {
        HearthPalette.parchment.overlay(
            VStack(spacing: 5) {
                Image(systemName: "photo")
                    .font(.system(size: 17))
                    .foregroundStyle(HearthPalette.fawn.opacity(0.7))
                Text(src)
                    .font(.system(size: 10))
                    .foregroundStyle(HearthPalette.fawn)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
        )
    }
}
