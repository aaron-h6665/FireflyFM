//
//  HQHomeView.swift
//  FireflyFM
//

import SwiftUI

struct HQHomeView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var schools: [School] = []
    @State private var showingProfile = false
    @State private var showingNewSchool = false
    @State private var showingSignOutConfirmation = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        topBar
                        mySchoolsHeader
                        schoolCircles
                        hqWorkspaceGrid

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
                .refreshable { await loadSchools() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingNewSchool) {
                NewSchoolCreationView {
                    Task { await loadSchools() }
                }
            }
            .confirmationDialog(
                "Sign out of FireflyFM?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authManager.signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again to manage your schools.")
            }
            .task { await loadSchools() }
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                Text("FireflyFM")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }

            Spacer()

            Button {
                showingProfile = true
            } label: {
                if let avatarUrl = appSession.profile?.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        profilePlaceholder
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                } else {
                    profilePlaceholder
                        .frame(width: 38, height: 38)
                }
            }

            Button {
                showingSignOutConfirmation = true
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(AppConstants.Colors.card)
            .overlay(
                Text(appSession.profile?.initials ?? "HQ")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            )
    }

    private var mySchoolsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Schools")
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            HStack(spacing: 12) {
                Button {
                    showingNewSchool = true
                } label: {
                    Label("New School", systemImage: "plus")
                }
                .buttonStyle(HQPrimaryButtonStyle())

                NavigationLink {
                    HQSchoolsListView(schools: schools)
                } label: {
                    Label("View All", systemImage: "square.grid.2x2")
                }
                .buttonStyle(HQSecondaryButtonStyle())
            }
        }
    }

    private var schoolCircles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                Button {
                    showingNewSchool = true
                } label: {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(AppConstants.Colors.card)
                            .frame(width: 78, height: 78)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                            )
                        Text("Create")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.78))
                    }
                    .frame(width: 90)
                }
                .buttonStyle(.plain)

                if isLoading {
                    ProgressView()
                        .tint(AppConstants.Colors.accessibleYellow)
                        .frame(width: 78, height: 78)
                } else {
                    ForEach(schools) { school in
                        NavigationLink {
                            CommunityView(school: school)
                        } label: {
                            SchoolCircleButton(school: school)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var hqWorkspaceGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Franchise Tools")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    FranchiseOverviewView()
                } label: {
                    HQWorkspaceCard(title: "Overview", subtitle: "Records by school", icon: "chart.bar.xaxis")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    EducationAssignmentView()
                } label: {
                    HQWorkspaceCard(title: "Education", subtitle: "Curriculum and training", icon: "graduationcap.fill")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DocumentFeedbackLoopView()
                } label: {
                    HQWorkspaceCard(title: "Documents", subtitle: "Assign and verify files", icon: "doc.badge.gearshape")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ChildrenView()
                } label: {
                    HQWorkspaceCard(title: "Children", subtitle: "Cross-school roster", icon: "figure.2.and.child.holdinghands")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func loadSchools() async {
        isLoading = true
        errorMessage = nil

        do {
            schools = try await SchoolService.shared.fetchSchoolsForHQ()
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load schools", error)
            isLoading = false
        }
    }
}

private struct SchoolCircleButton: View {
    let school: School

    var body: some View {
        VStack(spacing: 8) {
            SchoolAvatarView(school: school, size: 78)
            Text(school.name)
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.86))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 92)
        }
    }
}

struct SchoolAvatarView: View {
    let school: School
    let size: CGFloat

    var body: some View {
        Group {
            if let profileImageUrl = school.profileImageUrl, let url = URL(string: profileImageUrl) {
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
        .overlay(Circle().stroke(AppConstants.Colors.accessibleYellow.opacity(0.32), lineWidth: 2))
    }

    private var avatarFallback: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [AppConstants.Colors.card, AppConstants.Colors.accessibleYellow.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(initials)
                    .font(.system(size: max(16, size * 0.28), weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private var initials: String {
        let parts = school.name.split(separator: " ").prefix(2).compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "S" : value
    }
}

private struct HQWorkspaceCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.62))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }
}

private struct HQSchoolsListView: View {
    let schools: [School]

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            List(schools) { school in
                NavigationLink {
                    CommunityView(school: school)
                } label: {
                    HStack(spacing: 12) {
                        SchoolAvatarView(school: school, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(school.name)
                                .font(.headline)
                            if let description = school.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Schools")
    }
}

private struct NewSchoolCreationView: View {
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var schoolName = ""
    @State private var directorName = ""
    @State private var directorEmail = ""
    @State private var result: SchoolCreationResult?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("School") {
                    TextField("School name", text: $schoolName)
                }

                Section("School Director Invite") {
                    TextField("Director name", text: $directorName)
                    TextField("Director email", text: $directorEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let result {
                    Section("Invite Link") {
                        Text(result.inviteUrl ?? "fireflyfm://role-invite?token=\(result.inviteToken)")
                            .font(.footnote.monospaced())
                        ShareLink(item: result.inviteUrl ?? "fireflyfm://role-invite?token=\(result.inviteToken)") {
                            Label("Share director sign-in link", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New School")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onCreated()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating" : "Create") { create() }
                        .disabled(schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || directorEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func create() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let created = try await SchoolService.shared.createSchoolWithDirectorInvite(
                    name: schoolName,
                    directorEmail: directorEmail,
                    directorName: directorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : directorName
                )
                await MainActor.run {
                    result = created
                    isSaving = false
                    onCreated()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not create school", error)
                }
            }
        }
    }
}

private struct HQPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppConstants.Colors.accessibleYellow.opacity(configuration.isPressed ? 0.72 : 1))
            .cornerRadius(8)
    }
}

private struct HQSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppConstants.Colors.card.opacity(configuration.isPressed ? 0.72 : 1))
            .cornerRadius(8)
    }
}

struct FranchiseOverviewView: View {
    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Franchise Overview")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    Text("A flexible dashboard shell for check-ins, fire drill records, incident reports, franchise fees, EEC licenses, and date/school filters.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.68))

                    ForEach(["Check-in / Check-out", "Fire Drills", "Incident Reports", "Franchise Fees", "EEC Licenses"], id: \.self) { title in
                        HStack {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Text("Ready")
                                .font(.caption.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppConstants.Colors.accessibleYellow)
                                .clipShape(Capsule())
                        }
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppConstants.Colors.card, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct EducationAssignmentView: View {
    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 44))
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Text("Education Assignments")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text("HQ curriculum and director/teacher training reuse the existing curriculum workflow. File, video, link, review, and feedback loops can expand from this surface.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Education")
    }
}

#Preview {
    HQHomeView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(AppSessionManager())
}
