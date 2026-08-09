//
//  ImageActions.swift
//  Hearth
//
//  The long-press menu on a drawing: share, save, copy. One definition, used
//  by both the timeline card and the full-screen viewer, so the two never
//  drift into offering different things for the same picture.
//
//  Everything here works on the IMAGE rather than its URL. The asset lives on
//  a host only reachable inside the house, so a shared link would be dead the
//  moment it left the phone -- and useless in the one place someone actually
//  wants to send a picture.
//
//  The image is loaded once and held, rather than fetched when the menu is
//  opened: `ShareLink` needs its item at construction, and a menu whose share
//  button appears a beat late is worse than one that is simply ready. The
//  fetch is nearly free anyway, since RemoteImage has already put the bytes in
//  URLCache by the time a long press is possible.
//

import SwiftUI
import Photos

@MainActor
@Observable
public final class ImageAsset {
    private(set) var image: Image?
    private(set) var uiImage: UIImage?
    public var saveResult: String?

    public func load(src: String) async {
        guard uiImage == nil, let url = hearthAssetURL(src) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let loaded = UIImage(data: data) else { return }
        uiImage = loaded
        image = Image(uiImage: loaded)
    }

    public func copyToPasteboard() {
        guard let uiImage else { return }
        UIPasteboard.general.image = uiImage
        saveResult = "Copied"
    }

    /// Add-only access, so the app asks for the narrowest permission that does
    /// the job and never gains the ability to read the operator's library.
    public func saveToPhotos() {
        guard let uiImage else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.saveResult = "Photos access was declined" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            } completionHandler: { ok, _ in
                Task { @MainActor in
                    self.saveResult = ok ? "Saved to Photos" : "Could not save"
                }
            }
        }
    }
}

/// Long press on any drawing to get the same three actions.
///
/// `addToPrompt` is passed in rather than assumed: the card can hand the
/// picture back to the composer, and the viewer has no composer to hand it to.
/// Nil hides the item entirely rather than showing a dead one.
public struct ImageActionsMenu: ViewModifier {
    public let asset: ImageAsset
    public let prompt: String
    public var addToPrompt: (() -> Void)?

    public func body(content: Content) -> some View {
        content.contextMenu {
            if let image = asset.image {
                ShareLink(item: image,
                          preview: SharePreview(prompt.isEmpty ? "From the easel" : prompt,
                                                image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button { asset.saveToPhotos() } label: {
                    Label("Save to Photos", systemImage: "photo.badge.plus")
                }
                Button { asset.copyToPasteboard() } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if let addToPrompt {
                    Divider()
                    Button(action: addToPrompt) {
                        Label("Add to prompt", systemImage: "text.badge.plus")
                    }
                }
            }
        }
    }
}

public extension View {
    func imageActions(_ asset: ImageAsset, prompt: String,
                      addToPrompt: (() -> Void)? = nil) -> some View {
        modifier(ImageActionsMenu(asset: asset, prompt: prompt, addToPrompt: addToPrompt))
    }
}

/// A brief confirmation, because Save and Copy are otherwise silent and the
/// operator has no way to tell whether the long press did anything.
public struct ImageActionToast: View {
    public let text: String

    public var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.black.opacity(0.72), in: Capsule())
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
