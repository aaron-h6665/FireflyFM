import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

enum MediaLibrarySaveError: LocalizedError {
    case permissionDenied
    case unsupportedMedia
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photos access is not available. Enable it in Settings to save media."
        case .unsupportedMedia:
            return "This attachment cannot be saved to Photos."
        case .invalidImage:
            return "The photo could not be read."
        }
    }
}

enum MediaLibrarySaver {
    static func save(
        remoteURL: URL,
        contentType: String?,
        fileName: String? = nil
    ) async throws {
        let authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus
        if authorization == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            status = authorization
        }

        guard status == .authorized || status == .limited else {
            throw MediaLibrarySaveError.permissionDenied
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        let fileExtension = fileName
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0 }
        let resolvedType = contentType
            ?? response.mimeType
            ?? fileExtension.flatMap { UTType(filenameExtension: $0)?.preferredMIMEType }
            ?? ""

        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        if resolvedType.hasPrefix("image/") {
            guard let image = UIImage(contentsOfFile: temporaryURL.path) else {
                throw MediaLibrarySaveError.invalidImage
            }
            try await performChanges {
                _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } else if resolvedType.hasPrefix("video/") {
            try await performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: temporaryURL)
            }
        } else {
            throw MediaLibrarySaveError.unsupportedMedia
        }
    }

    private static func performChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: MediaLibrarySaveError.unsupportedMedia)
                }
            }
        }
    }
}
