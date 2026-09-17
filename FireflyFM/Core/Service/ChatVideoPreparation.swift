import AVFoundation
import Foundation

struct PreparedChatVideo {
    let url: URL
    let isTemporary: Bool
}

enum ChatVideoPreparation {
    static let maximumDuration: TimeInterval = 120

    static func prepare(_ sourceURL: URL) async throws -> PreparedChatVideo {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw ChatVideoPreparationError.unreadable
        }
        guard duration <= maximumDuration else {
            throw ChatVideoPreparationError.tooLong(maximumSeconds: Int(maximumDuration))
        }

        if try fileSize(at: sourceURL) <= UploadPolicy.maxFileBytes {
            return PreparedChatVideo(url: sourceURL, isTemporary: false)
        }

        for preset in [AVAssetExportPresetMediumQuality, AVAssetExportPresetLowQuality] {
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { continue }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("FireflyChatVideo-\(UUID().uuidString)")
                .appendingPathExtension("mp4")
            try? FileManager.default.removeItem(at: outputURL)
            exporter.shouldOptimizeForNetworkUse = true

            do {
                try await exporter.export(to: outputURL, as: .mp4)
                if try fileSize(at: outputURL) <= UploadPolicy.maxFileBytes {
                    return PreparedChatVideo(url: outputURL, isTemporary: true)
                }
                try? FileManager.default.removeItem(at: outputURL)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: outputURL)
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        throw ChatVideoPreparationError.couldNotFit(
            maximumSize: UploadPolicy.maxFileSizeDescription
        )
    }

    private static func fileSize(at url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize {
            return fileSize
        }
        return try Data(contentsOf: url, options: .mappedIfSafe).count
    }
}

enum ChatVideoPreparationError: LocalizedError {
    case unreadable
    case tooLong(maximumSeconds: Int)
    case couldNotFit(maximumSize: String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "This video could not be read. Try a different video."
        case .tooLong(let maximumSeconds):
            "Choose a video that is \(maximumSeconds / 60) minutes or shorter."
        case .couldNotFit(let maximumSize):
            "This video is still larger than \(maximumSize) after compression. Try trimming it and send again."
        }
    }
}
