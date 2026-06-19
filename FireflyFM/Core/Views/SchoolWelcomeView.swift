//
//  SchoolWelcomeView.swift
//  FireflyFM
//

import SwiftUI

struct SchoolWelcomeView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager

    @State private var schoolCode = ""
    @State private var isJoining = false
    @State private var showingSignOutConfirmation = false
    @State private var errorMessage: String?

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
                                .foregroundColor(.white)

                            Text("Join your school workspace to unlock chats, events, newsletters, paperwork, and notifications.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.72))
                        }

                        panel("Join Your School", systemImage: "building.2.crop.circle") {
                            TextField("School code", text: $schoolCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(AppConstants.Colors.background.opacity(0.55))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                                .tint(AppConstants.Colors.accessibleYellow)

                            Button {
                                joinSchool()
                            } label: {
                                Label(isJoining ? "Joining" : "Join School", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SchoolPrimaryButtonStyle())
                            .disabled(schoolCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        panel("School Information", systemImage: "info.circle.fill") {
                            Text("Your school director will provide the code that connects you to the correct school server.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        panel("About FireflyFM", systemImage: "sparkles") {
                            Text("FireflyFM connects directors, teachers, and parents through one private school workspace.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        panel("Schedule School Tour", systemImage: "calendar.badge.plus") {
                            Text("Tour scheduling can be linked here when the school provides a booking page.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Button("Sign Out") {
                            showingSignOutConfirmation = true
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                    }
                    .padding()
                }
            }
            .confirmationDialog(
                "Sign out of FireflyFM?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        appSession.clear()
                        await authManager.signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again before joining a school.")
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

        isJoining = true
        errorMessage = nil

        Task {
            do {
                _ = try await SchoolService.shared.joinSchool(code: code)
                await appSession.refresh()
                await MainActor.run {
                    isJoining = false
                    schoolCode = ""
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorMessage = AppErrorMessage.school("Could not join school", error)
                }
            }
        }
    }
}

private struct SchoolPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.accessibleYellow.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}
