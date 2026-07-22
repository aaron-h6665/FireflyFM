//
//  InvitesView.swift
//  FireflyFM
//

import SwiftUI

struct InvitesView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var invites: [SchoolInvite] = []
    @State private var selectedRole: SchoolRole = .parent
    @State private var maxUses = 1
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Create role-bound school join codes for parents and teachers.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.65))

                    createPanel

                    Text("Active Codes")
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.primaryText)

                    if isLoading {
                        ProgressView().tint(AppConstants.Colors.accessibleYellow)
                    } else if invites.isEmpty {
                        emptyPanel("No invites yet.")
                    } else {
                        ForEach(invites) { invite in
                            inviteCard(invite)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Invites")
        .task {
            await loadInvites()
        }
        .refreshable {
            await loadInvites()
        }
    }

    private var createPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Role", selection: $selectedRole) {
                Text("Parent").tag(SchoolRole.parent)
                Text("Teacher").tag(SchoolRole.teacher)
            }
            .pickerStyle(.segmented)

            Stepper("Uses: \(maxUses)", value: $maxUses, in: 1...100)
                .foregroundColor(AppConstants.Colors.primaryText)

            Button {
                createInvite()
            } label: {
                Label("Create Code", systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(InvitePrimaryButtonStyle())
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func inviteCard(_ invite: SchoolInvite) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(invite.code)
                    .font(.title3.monospaced().bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .textSelection(.enabled)
                Text("\(invite.role.title) • \(invite.useCount)/\(invite.maxUses ?? 0) used")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
            }
            Spacer()
            ShareLink(item: invite.code) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func emptyPanel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
    }

    @MainActor
    private func loadInvites() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            invites = try await SchoolService.shared.fetchInvites(schoolId: schoolId)
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load invites", error)
            isLoading = false
        }
    }

    private func createInvite() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        Task {
            do {
                _ = try await SchoolService.shared.createInvite(schoolId: schoolId, role: selectedRole, maxUses: maxUses)
                await loadInvites()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not create invite", error)
                }
            }
        }
    }
}

private struct InvitePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(AppConstants.Colors.primaryActionText)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.primaryAction.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}
