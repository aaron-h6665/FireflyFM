import SwiftUI

struct InviteCoordinatorView: View {
    let invite: PendingInvite

    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @Environment(\.dismiss) private var dismiss

    @State private var preview: RoleInvitePreview?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                if case .role = invite, preview == nil, errorMessage == nil {
                    ProgressView("Checking invitation")
                } else {
                    invitationSummary
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)

                    if case .role = invite {
                        Button("Sign in with another account") {
                            dismiss()
                            Task { await authManager.signOut() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()

                if errorMessage == nil {
                    Button(isLoading ? "Joining…" : "Accept Invitation") { accept() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppConstants.Colors.primaryAction)
                        .disabled(isLoading || (isRoleInvite && preview == nil))
                        .frame(maxWidth: .infinity)
                }

                Button("Not Now", role: .cancel) {
                    deepLinkManager.clear(invite)
                    dismiss()
                }
                .disabled(isLoading)
            }
            .padding(24)
            .navigationTitle("School Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadPreviewIfNeeded() }
        }
    }

    @ViewBuilder
    private var invitationSummary: some View {
        switch invite {
        case .role:
            if let preview {
                VStack(spacing: 8) {
                    Text(preview.schoolName).font(.title2.bold())
                    Text("Join as \(preview.role.inviteDisplayName)").font(.headline)
                    if let expiresAt = preview.expiresAt {
                        Text("Invitation expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
            }
        case .school:
            VStack(spacing: 8) {
                Text("Join this school").font(.title2.bold())
                Text("Your invitation code is ready to be accepted.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var isRoleInvite: Bool {
        if case .role = invite { return true }
        return false
    }

    @MainActor
    private func loadPreviewIfNeeded() async {
        guard case .role(let token) = invite else { return }
        do {
            preview = try await SchoolService.shared.previewRoleInvite(token: token)
        } catch {
            errorMessage = AppErrorMessage.school("Could not open invitation", error)
        }
    }

    private func accept() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let membership: SchoolMembership
                switch invite {
                case .role(let token):
                    membership = try await SchoolService.shared.acceptRoleInvite(token: token)
                case .school(let code):
                    membership = try await SchoolService.shared.joinSchool(code: code)
                }
                await appSession.refresh(selecting: membership.id)
                await MainActor.run {
                    deepLinkManager.clear(invite)
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = AppErrorMessage.school("Could not accept invitation", error)
                }
            }
        }
    }
}

private extension SchoolRole {
    var inviteDisplayName: String {
        switch self {
        case .parent: "Parent"
        case .teacher: "Teacher"
        case .schoolDirector: "School Director"
        case .hqDirector: "HQ Director"
        }
    }
}
