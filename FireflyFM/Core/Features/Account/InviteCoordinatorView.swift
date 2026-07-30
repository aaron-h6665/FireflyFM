import SwiftUI

struct InviteCoordinatorView: View {
    let invite: PendingInvite

    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @Environment(\.dismiss) private var dismiss

    @State private var model = InviteCoordinatorModel()

    private var preview: RoleInvitePreview? { model.preview }
    private var isLoading: Bool { model.isLoading }
    private var errorMessage: String? { model.errorMessage }

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
        await model.loadPreview(invite: invite)
    }

    private func accept() {
        Task {
            if let membership = await model.accept(invite: invite) {
                await appSession.refresh(selecting: membership.id)
                deepLinkManager.clear(invite)
                dismiss()
            }
        }
    }
}
