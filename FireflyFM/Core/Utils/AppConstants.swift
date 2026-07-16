//
//  AppConstants.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation
import SwiftUI
import Supabase

struct AppConstants {
    static let projectURLString = "https://dewlupfhausbxyvbvdix.supabase.co"
    static let projectAPIKey = "sb_publishable_XLQLdj4OkY27aSBSEqVtBA_mkZO0aY_"
    
    static let supabase = SupabaseClient(
        supabaseURL: URL(string: projectURLString)!,
        supabaseKey: projectAPIKey,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )

    struct Features {
        /// Payment-provider integration is intentionally bypassed for the MVP so
        /// parent and director onboarding can be exercised end to end.
        static let paymentsEnabled = false
    }
    
    struct Colors {
            /// The main dark background color
            static let background = Color(red: 0.10, green: 0.15, blue: 0.20)
            
            /// The slightly lighter color used for cards and text fields
            static let card = Color(red: 0.15, green: 0.22, blue: 0.28)
            
            /// High-contrast yellow for primary actions and accents (WCAG AAA compliant)
            static let accessibleYellow = Color(red: 1.0, green: 0.85, blue: 0.20)
        }
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
