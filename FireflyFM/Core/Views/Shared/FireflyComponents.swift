import SwiftUI

struct FireflyScreen<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            FireflyTheme.Colors.background.ignoresSafeArea()
            content
        }
    }
}

struct FireflySectionCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(FireflyTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FireflyTheme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius, style: .continuous)
                    .stroke(FireflyTheme.Colors.separator.opacity(0.65), lineWidth: 1)
            }
    }
}

struct FireflyEmptyState: View {
    let title: String
    var message: String? = nil
    var systemImage: String? = nil

    var body: some View {
        VStack(spacing: FireflyTheme.Layout.spacingMedium) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(FireflyTheme.Colors.secondaryText.opacity(0.55))
            }
            Text(title)
                .font(.headline)
                .foregroundColor(FireflyTheme.Colors.primaryText)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(FireflyTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(FireflyTheme.Layout.spacingLarge)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(FireflyTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct FireflyInlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("inline-error")
    }
}

struct FireflySearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: FireflyTheme.Layout.spacingSmall) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(FireflyTheme.Colors.secondaryText)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(FireflyTheme.Colors.primaryText)
                .tint(FireflyTheme.Colors.primaryAction)
                .accessibilityIdentifier("search-field")
        }
        .padding(.horizontal, FireflyTheme.Layout.controlPadding)
        .frame(minHeight: FireflyTheme.Layout.minimumTapTarget)
        .background(FireflyTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius, style: .continuous)
                .stroke(FireflyTheme.Colors.separator.opacity(0.65), lineWidth: 1)
        }
    }
}

struct FireflySchoolPicker: View {
    let schools: [School]
    @Binding var selectedSchoolId: UUID?
    var includesAllSchools = false

    var body: some View {
        HStack(spacing: FireflyTheme.Layout.spacingMedium) {
            Label("School", systemImage: "building.2")
                .font(.subheadline.bold())
                .foregroundColor(FireflyTheme.Colors.secondaryText)
            Spacer()
            Picker("School", selection: $selectedSchoolId) {
                if includesAllSchools {
                    Text("All Schools").tag(Optional<UUID>.none)
                }
                ForEach(schools) { school in
                    Text(school.name).tag(Optional(school.id))
                }
            }
            .pickerStyle(.menu)
            .tint(FireflyTheme.Colors.primaryAction)
        }
        .padding(FireflyTheme.Layout.controlPadding)
        .background(FireflyTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius, style: .continuous))
        .accessibilityIdentifier("school-picker")
    }
}

struct SchoolAvatarView: View {
    let school: School
    let size: CGFloat

    var body: some View {
        Group {
            if let url = school.profileImageUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarFallback
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(FireflyTheme.Colors.fireflyBlue.opacity(0.28), lineWidth: 1))
        .accessibilityLabel(school.name)
    }

    private var avatarFallback: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [FireflyTheme.Colors.wingMist, FireflyTheme.Colors.wingBlue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(InitialsFormatter.initials(for: school.name, fallback: "S"))
                    .font(.system(size: max(16, size * 0.28), weight: .bold))
                    .foregroundColor(FireflyTheme.Colors.primaryText)
            }
    }
}
