//
//  AppConstants.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation

/// Compatibility facade for existing call sites. New code should use
/// `AppConfiguration` for runtime dependencies and `FireflyTheme` for UI.
struct AppConstants {
    static let projectURLString = AppConfiguration.projectURLString
    static let projectAPIKey = AppConfiguration.projectAPIKey
    static let supabase = AppConfiguration.supabase

    typealias Colors = FireflyTheme.Colors
    typealias Layout = FireflyTheme.Layout
}

enum UploadPolicy {
    static let maxFileBytes = 10 * 1024 * 1024
    static let maxFileSizeDescription = "10 MB"

    static func validate(data: Data, fileName: String) throws {
        try validate(byteCount: data.count, fileName: fileName)
    }

    static func validate(fileURL: URL) throws {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize {
            try validate(byteCount: fileSize, fileName: displayName(for: fileURL))
        }
    }

    static func validate(byteCount: Int, fileName: String) throws {
        guard byteCount <= maxFileBytes else {
            throw UploadValidationError.fileTooLarge(
                fileName: fileName.isEmpty ? "This file" : fileName,
                byteCount: byteCount,
                maximumByteCount: maxFileBytes
            )
        }
    }

    private static func displayName(for fileURL: URL) -> String {
        fileURL.lastPathComponent.isEmpty ? "This file" : fileURL.lastPathComponent
    }
}

enum UploadValidationError: LocalizedError {
    case fileTooLarge(fileName: String, byteCount: Int, maximumByteCount: Int)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let fileName, let byteCount, let maximumByteCount):
            let actualSize = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
            let maximumSize = maximumByteCount == UploadPolicy.maxFileBytes
                ? UploadPolicy.maxFileSizeDescription
                : ByteCountFormatter.string(fromByteCount: Int64(maximumByteCount), countStyle: .file)
            return "\(fileName) is \(actualSize). FireflyFM currently accepts files up to \(maximumSize)."
        }
    }
}
