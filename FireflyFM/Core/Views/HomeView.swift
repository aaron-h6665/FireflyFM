//
//  HomeView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var newsletters: [NewsletterPost] = []
    @State private var isLoading = false
    @State private var showingProfile = false
    @State private var showingNewsletterComposer = false
    @State private var showingSignOutConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        workspaceStrip
                        newsletterSection
                    }
                    .padding()
                }
                .refreshable {
                    await loadNewsletters()
                }

                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        message: "You will need to sign in again to access your school workspace.",
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingNewsletterComposer) {
                NewsletterComposerView {
                    Task { await loadNewsletters() }
                }
            }
            .task {
                await loadNewsletters()
            }
            .onChange(of: appSession.activeMembershipId) { _, _ in
                Task { await loadNewsletters() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Home")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Spacer()

                Button {
                    showingProfile = true
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }

                Button {
                    showingSignOutConfirmation = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.82))
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appSession.activeSchool?.name ?? "FireflyFM")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
                Spacer()
            }

            if appSession.canSwitchSchools {
                Picker("Active School", selection: Binding(
                    get: { appSession.activeMembershipId ?? appSession.memberships.first?.membership.id },
                    set: { newValue in
                        if let newValue,
                           let context = appSession.memberships.first(where: { $0.membership.id == newValue }) {
                            appSession.setActiveContext(context)
                        }
                    }
                )) {
                    ForEach(appSession.memberships) { context in
                        Text(context.school.name).tag(Optional(context.membership.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(AppConstants.Colors.accessibleYellow)
            }
        }
    }

    private var workspaceStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspaces")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(workspaces) { workspace in
                        NavigationLink {
                            workspace.destination
                        } label: {
                            WorkspaceCard(workspace: workspace)
                        }
                    }
                }
            }
        }
    }

    private var newsletterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Newsletters")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if appSession.role?.canManageSchool == true {
                    Button {
                        showingNewsletterComposer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }

            if isLoading {
                ProgressView().tint(AppConstants.Colors.accessibleYellow)
            } else if newsletters.isEmpty {
                emptyPanel("No newsletters yet")
            } else {
                ForEach(newsletters) { post in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(post.body)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.72))
                        if let createdAt = post.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var workspaces: [WorkspaceItem] {
        switch appSession.role {
        case .parent:
            return [
                WorkspaceItem(title: "Work", subtitle: "Assignments and feedback", icon: "checklist.checked", destination: AnyView(AssignmentsView(surface: .all))),
                WorkspaceItem(title: "Children", subtitle: "Profiles and records", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView())),
                WorkspaceItem(title: "Payments", subtitle: "Invoices and receipts", icon: "creditcard.fill", destination: AnyView(PaymentsView()))
            ]
        case .teacher:
            return [
                WorkspaceItem(title: "Work", subtitle: "Assignments and feedback", icon: "checklist.checked", destination: AnyView(AssignmentsView(surface: .all))),
                WorkspaceItem(title: "Children", subtitle: "Check-in and activity", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView()))
            ]
        case .schoolDirector, .hqDirector:
            return [
                WorkspaceItem(title: "Work", subtitle: "Assign, submit, and review", icon: "checklist.checked", destination: AnyView(AssignmentsView(surface: .all))),
                WorkspaceItem(title: "Children", subtitle: "Attendance and logs", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView())),
                WorkspaceItem(title: "Invites", subtitle: "School join codes", icon: "person.badge.key.fill", destination: AnyView(InvitesView()))
            ]
        case .none:
            return []
        }
    }

    private func emptyPanel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
    }

    @MainActor
    private func loadNewsletters() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            newsletters = try await SchoolWorkflowService.shared.fetchNewsletters(schoolId: schoolId)
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load newsletters", error)
            isLoading = false
        }
    }
}

private struct WorkspaceItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let destination: AnyView
}

private struct WorkspaceCard: View {
    let workspace: WorkspaceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: workspace.icon)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text(workspace.title)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .lineLimit(1)
            Text(workspace.subtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.58))
                .lineLimit(2)
        }
        .frame(width: 148, height: 112, alignment: .topLeading)
        .padding(12)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }
}

private struct NewsletterComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    var onSaved: () -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Newsletter") {
                    TextField("Title", text: $title)
                    TextField("Body", text: $bodyText, axis: .vertical)
                        .lineLimit(5...10)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Newsletter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Post") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.createNewsletter(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not post newsletter", error)
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(AppSessionManager())
}
