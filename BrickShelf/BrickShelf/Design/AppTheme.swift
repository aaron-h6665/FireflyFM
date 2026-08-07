import SwiftUI

enum AppTheme {
    static let navy = Color(red: 0.035, green: 0.11, blue: 0.20)
    static let blue = Color(red: 0.08, green: 0.43, blue: 0.73)
    static let teal = Color(red: 0.12, green: 0.58, blue: 0.53)
    static let yellow = Color(red: 0.98, green: 0.72, blue: 0.16)
    static let coral = Color(red: 0.93, green: 0.30, blue: 0.23)
    static let canvas = Color(uiColor: .systemGroupedBackground)
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func appCard() -> some View { modifier(CardModifier()) }
}

struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .appCard()
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity)
            .appCard()
    }
}
