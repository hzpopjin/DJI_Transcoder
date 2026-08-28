import Combine
import Photos
import SwiftUI
import UIKit

struct AssetThumbnailView: View {
    let localIdentifier: String
    var mediaKind: MediaKind?
    var cornerRadius: CGFloat = 12

    @StateObject private var loader = AssetThumbnailLoader()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(Color(.tertiarySystemFill))

                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image(systemName: mediaKind?.symbol ?? "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let mediaKind, mediaKind != .photo {
                    Image(systemName: mediaKind.symbol)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.68), in: .circle)
                        .padding(5)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(.rect(cornerRadius: cornerRadius))
        }
        .contentShape(.rect(cornerRadius: cornerRadius))
        .task(id: localIdentifier) {
            loader.load(localIdentifier: localIdentifier)
        }
        .onDisappear { loader.cancel() }
        .accessibilityHidden(true)
    }
}

@MainActor
private final class AssetThumbnailLoader: ObservableObject {
    @Published var image: UIImage?

    private let manager = PHImageManager.default()
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var loadedIdentifier: String?

    func load(localIdentifier: String) {
        guard loadedIdentifier != localIdentifier else { return }
        cancel()
        loadedIdentifier = localIdentifier
        image = nil

        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        requestID = manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 240, height: 240),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let image else { return }
            Task { @MainActor [weak self] in
                guard self?.loadedIdentifier == localIdentifier else { return }
                self?.image = image
            }
        }
    }

    func cancel() {
        if requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
        loadedIdentifier = nil
    }
}
