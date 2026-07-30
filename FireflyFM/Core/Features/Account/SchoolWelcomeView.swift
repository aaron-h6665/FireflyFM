//
//  SchoolWelcomeView.swift
//  FireflyFM
//

import SwiftUI

struct SchoolWelcomeView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var deepLinkManager: DeepLinkManager

    @State private var schoolCode = ""
    @State private var roleInviteCode = ""
    @State private var model = SchoolWelcomeModel()
    @State private var showingSignOutConfirmation = false

    private var isJoining: Bool { model.isJoining }
    private var isAcceptingRoleInvite: Bool { model.isAcceptingRoleInvite }
    private var errorMessage: String? { model.errorMessage }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 76, height: 76)

                            Text("Welcome to FireflyFM")
                                .font(.largeTitle.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)

                            Text("Join your school workspace to unlock chats, events, newsletters, paperwork, and notifications.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                        }

                        if isAcceptingRoleInvite {
                            panel("Accepting Invite", systemImage: "person.badge.key.fill") {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .tint(AppConstants.Colors.accessibleYellow)
                                    Text("Connecting your account to the assigned school...")
                                        .font(.subheadline)
                                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                                }
                            }
                        }

                        panel("Accept an Invitation", systemImage: "person.badge.key.fill") {
                            Text("If a director or HQ administrator invited you by email, paste the one-time code they generated.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))

                            TextField("Invitation code", text: $roleInviteCode)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(AppConstants.Colors.background.opacity(0.55))
                                .cornerRadius(8)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)

                            Button {
                                acceptRoleInvitation()
                            } label: {
                                Label(isAcceptingRoleInvite ? "Accepting" : "Accept Invitation", systemImage: "checkmark.seal.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SchoolPrimaryButtonStyle())
                            .disabled(roleInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAcceptingRoleInvite)
                        }

                        panel("Join With a General School Code", systemImage: "building.2.crop.circle") {
                            TextField("School code", text: $schoolCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(AppConstants.Colors.background.opacity(0.55))
                                .cornerRadius(8)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)

                            Button {
                                joinSchool()
                            } label: {
                                Label(isJoining ? "Joining" : "Join School", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SchoolPrimaryButtonStyle())
                            .disabled(schoolCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)

                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        panel("School Information", systemImage: "info.circle.fill") {
                            Text("Role invitations are email-bound and create the correct onboarding checklist only after you accept. General school codes are for schools that explicitly use open code-based joining.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                        }

                        panel("About FireflyFM", systemImage: "sparkles") {
                            Text("FireflyFM connects directors, teachers, and parents through one private school workspace.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                        }

                        panel("Schedule School Tour", systemImage: "calendar.badge.plus") {
                            Text("Tour scheduling can be linked here when the school provides a booking page.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                        }

                        Button("Sign Out") {
                            showingSignOutConfirmation = true
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                    }
                    .padding()
                }

                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        message: "You will need to sign in again before joining a school.",
                        onCancel: { showingSignOutConfirmation = false },
                        onSignOut: {
                            showingSignOutConfirmation = false
                            Task { await authManager.signOut() }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(2)
                }
            }
        }
    }

    private func panel<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func joinSchool() {
        let code = schoolCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        Task {
            if let membership = await model.join(code: code) {
                await appSession.refresh(selecting: membership.id)
                schoolCode = ""
            }
        }
    }

    private func acceptRoleInvitation() {
        let code = roleInviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        Task {
            if let membership = await model.acceptRoleInvite(token: code) {
                await appSession.refresh(selecting: membership.id)
                roleInviteCode = ""
            }
        }
    }

}

private struct SchoolPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(AppConstants.Colors.primaryActionText)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.primaryAction.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}
