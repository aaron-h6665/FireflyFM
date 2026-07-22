//
//  AppConstants.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation
import SwiftUI
import Supabase
import UIKit

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
        static let brandNavy = Color(hex: 0x28276F)
        static let fireflyBlue = Color(hex: 0x6881AF)
        static let wingBlue = Color(hex: 0xA9C3E4)
        static let wingMist = Color(hex: 0xBEE6F5)
        static let aqua = Color(hex: 0x85CEDE)
        static let fireflyGlow = Color(hex: 0xFBB561)
        static let softGlow = Color(hex: 0xFDCC90)

        static let background = adaptive(light: 0xF4F8FB, dark: 0x10122C)
        static let card = adaptive(light: 0xFFFFFF, dark: 0x1C2050)
        static let raised = adaptive(light: 0xEAF4F8, dark: 0x242B61)
        static let primaryText = adaptive(light: 0x20204F, dark: 0xF6FAFD)
        static let secondaryText = adaptive(light: 0x5D6788, dark: 0xC3D2E6)
        static let primaryAction = adaptive(light: 0x28276F, dark: 0x85CEDE)
        static let primaryActionText = adaptive(light: 0xFFFFFF, dark: 0x28276F)
        static let separator = adaptive(light: 0xD7E1EA, dark: 0x343B72)

        /// Compatibility alias while older screens move to semantic tokens.
        static let accessibleYellow = fireflyGlow

        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            })
        }
    }

    struct Layout {
        static let cardRadius: CGFloat = 16
        static let controlRadius: CGFloat = 12
        static let minimumTapTarget: CGFloat = 44
    }
}

/// Semantic design-system entry point. `AppConstants` remains available while
/// existing screens migrate, but new UI should read tokens through this name.
typealias FireflyTheme = AppConstants

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
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
