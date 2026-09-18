import SwiftUI
import UIKit

enum FireflyTheme {
    enum Colors {
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
        static let success = adaptive(light: 0x247A52, dark: 0x78D6A6)
        static let warning = adaptive(light: 0x9A5A13, dark: 0xF6C276)
        static let danger = adaptive(light: 0xB3261E, dark: 0xFFB4AB)
        static let information = adaptive(light: 0x315E91, dark: 0xA9C3E4)
        static let attentionBackground = adaptive(light: 0xFFF2DD, dark: 0x4D351E)
        static let successBackground = adaptive(light: 0xE4F5EC, dark: 0x183B2B)
        static let dangerBackground = adaptive(light: 0xFDEBE9, dark: 0x4A2527)
        static let informationBackground = adaptive(light: 0xE6F0FA, dark: 0x243757)

        /// Compatibility alias while older screens move to semantic tokens.
        static let accessibleYellow = fireflyGlow

        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            })
        }
    }

    enum Layout {
        static let cardRadius: CGFloat = 16
        static let controlRadius: CGFloat = 12
        static let minimumTapTarget: CGFloat = 44
        static let spacingXSmall: CGFloat = 4
        static let spacingSmall: CGFloat = 8
        static let spacingMedium: CGFloat = 12
        static let spacingLarge: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let controlPadding: CGFloat = 12
    }

    enum Typography {
        static let screenTitle = Font.largeTitle.weight(.bold)
        static let sectionTitle = Font.headline
        static let rowTitle = Font.headline
        static let body = Font.subheadline
        static let supporting = Font.caption
        static let badge = Font.caption.weight(.semibold)
        static let monetaryValue = Font.title2.weight(.bold)
    }
}

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
