import AVFoundation
import SwiftUI
import UIKit

final class ChatVideoThumbnailProvider: @unchecked Sendable {
    static let shared = ChatVideoThumbnailProvider()

    private let cache = NSCache<NSURL, UIImage>()

    func thumbnail(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let requestedTime = CMTime(seconds: 0.25, preferredTimescale: 600)

        return await withCheckedContinuation { [weak self] continuation in
            generator.generateCGImageAsynchronously(for: requestedTime) { cgImage, _, _ in
                guard let self, let cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                let generated = UIImage(cgImage: cgImage)
                self.cache.setObject(generated, forKey: url as NSURL)
                continuation.resume(returning: generated)
            }
        }
    }
}

struct ChatVideoThumbnailView: View {
    let url: URL?

    @State private var thumbnail: UIImage?

    var body: some View {
        Rectangle()
            .fill(AppConstants.Colors.wingMist.opacity(0.5))
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.48))
                    .shadow(radius: 3)
            }
            .clipped()
            .task(id: url) {
                guard let url else { return }
                thumbnail = await ChatVideoThumbnailProvider.shared.thumbnail(for: url)
            }
    }
}
