import SwiftUI

struct TodayHeader: View {
    @EnvironmentObject private var appSession: AppSessionManager

    let title: String
    var subtitle: String? = nil
    let onProfile: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) {
            HStack {
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundColor(FireflyTheme.Colors.primaryText)
                    Text(subtitle ?? appSession.activeSchool?.name ?? "Your school")
                        .font(.subheadline)
                        .foregroundColor(FireflyTheme.Colors.secondaryText)
                }
                Spacer()
                NotificationBellButton()
                accountMenu
            }

            SchoolSwitcher()
        }
        .accessibilityIdentifier("today-header")
    }

    private var accountMenu: some View {
        Menu {
            Button("Profile", systemImage: "person.crop.circle", action: onProfile)
            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: onSignOut)
        } label: {
            Circle()
                .fill(FireflyTheme.Colors.wingMist)
                .frame(width: FireflyTheme.Layout.minimumTapTarget, height: FireflyTheme.Layout.minimumTapTarget)
                .overlay {
                    Text(appSession.profile?.initials ?? "FF")
                        .font(.caption.bold())
                        .foregroundColor(FireflyTheme.Colors.brandNavy)
                }
        }
        .accessibilityLabel("Account menu")
    }
}

struct SchoolSwitcher: View {
    @EnvironmentObject private var appSession: AppSessionManager

    var body: some View {
        if appSession.canSwitchSchools {
            Picker("Active School", selection: Binding(
                get: { appSession.activeMembershipId ?? appSession.memberships.first?.membership.id },
                set: { membershipId in
                    if let membershipId { appSession.switchActiveMembership(to: membershipId) }
                }
            )) {
                ForEach(appSession.memberships) { context in
                    Text(context.school.name).tag(Optional(context.membership.id))
                }
            }
            .pickerStyle(.menu)
            .tint(FireflyTheme.Colors.primaryAction)
            .accessibilityIdentifier("active-school-switcher")
        }
    }
}

struct TodayActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(color)
            Text(title)
                .font(.headline)
                .foregroundColor(FireflyTheme.Colors.primaryText)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(FireflyTheme.Colors.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .padding(FireflyTheme.Layout.cardPadding)
        .background(FireflyTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct MessagesSpotlightCard: View {
    let systemImage: String
    let message: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: FireflyTheme.Layout.spacingMedium) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(FireflyTheme.Colors.brandNavy)
                    .frame(width: 48, height: 48)
                    .background(FireflyTheme.Colors.fireflyGlow)
                    .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius, style: .continuous))
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
                    Text("Daily updates live in Messages")
                        .font(.headline)
                        .foregroundColor(FireflyTheme.Colors.primaryText)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(FireflyTheme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(FireflyTheme.Colors.primaryAction)
            }
            .padding(FireflyTheme.Layout.cardPadding)
            .background(
                LinearGradient(
                    colors: [FireflyTheme.Colors.card, FireflyTheme.Colors.wingMist.opacity(0.42)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("messages-spotlight")
    }
}

struct TodaySectionIntro: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(FireflyTheme.Colors.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundColor(FireflyTheme.Colors.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AssignmentShortcutCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: FireflyTheme.Layout.spacingMedium) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 46, height: 46)
                    .foregroundColor(FireflyTheme.Colors.brandNavy)
                    .background(FireflyTheme.Colors.fireflyGlow)
                    .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius))
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(FireflyTheme.Colors.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(FireflyTheme.Colors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(FireflyTheme.Colors.secondaryText)
            }
            .padding(FireflyTheme.Layout.cardPadding)
            .background(FireflyTheme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assignment-shortcut")
    }
}

struct WorkspaceLink<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: FireflyTheme.Layout.spacingMedium) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(FireflyTheme.Colors.primaryAction)
                    .frame(width: 48, height: 48)
                    .background(FireflyTheme.Colors.wingMist)
                    .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius))
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
                    Text(title).font(.headline).foregroundColor(FireflyTheme.Colors.primaryText)
                    Text(subtitle).font(.caption).foregroundColor(FireflyTheme.Colors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(FireflyTheme.Colors.secondaryText)
            }
            .padding(FireflyTheme.Layout.cardPadding)
            .background(FireflyTheme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
