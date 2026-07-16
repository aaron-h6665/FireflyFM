//
//  ContentView.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import SwiftUI
import CoreData
import Supabase

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var showSignUp = false
    @State private var signupSuccess = false
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .notDetermind:
                ZStack {
                    AppConstants.Colors.background.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    }
                }
            case .notAuthenticated:
                NavigationStack {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        
                        // Decorative Glow
                        VStack {
                            Circle()
                                .fill(AppConstants.Colors.accessibleYellow.opacity(0.15))
                                .frame(width: 400, height: 400)
                                .blur(radius: 60)
                                .offset(x: -150, y: -200)
                            Spacer()
                        }
                        
                        VStack(spacing: 40) {
                            Spacer()
                            
                            // Branding
                            VStack(spacing: 16) {
                                Image("Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 140, height: 140)
                                
                                VStack(spacing: 8) {
                                    Text("Firefly Care") // Update with your actual app name
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("Connecting directors, staff, and parents.")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.85)) // High contrast text
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                            
                            Spacer()
                            
                            // Navigation Buttons
                            VStack(spacing: 16) {
                                // Pushes to the Login View
                                NavigationLink(destination: LoginView()) {
                                    Text("Sign In")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(AppConstants.Colors.accessibleYellow)
                                        .foregroundColor(.black)
                                        .cornerRadius(12)
                                        .shadow(color: AppConstants.Colors.accessibleYellow.opacity(0.3), radius: 10, x: 0, y: 5)
                                }
                                
                                // Pushes to the Role Selection View
                                NavigationLink(destination: RoleSelectionView()) {
                                    Text("Create an Account")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(AppConstants.Colors.card)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                    }
                }
//                if showSignUp {
//                    SignUpView(
//                        showLogin: { 
//                            showSignUp = false 
//                        },
//                        onSignupSuccess: {
//                            signupSuccess = true
//                            showSignUp = false
//                        }
//                    )
//                } else {
//                    LoginView(
//                        showSignUp: { 
//                            showSignUp = true 
//                        },
//                        signupSuccess: signupSuccess
//                    )
//                }
            case .authenticated:
                if authManager.isSigningOut {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(AppConstants.Colors.accessibleYellow)
                            Text("Signing out...")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                        }
                    }
                } else if appSession.isLoading {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        ProgressView("Loading school")
                            .tint(AppConstants.Colors.accessibleYellow)
                            .foregroundColor(.white)
                    }
                } else if appSession.hasSchoolAccess {
                    if appSession.role?.usesAccessChecklist == true {
                        AccessChecklistGateView()
                    } else {
                        MainTabView()
                    }
                } else if let errorMessage = appSession.errorMessage {
                    SchoolAccessErrorView(message: errorMessage) {
                        Task { await appSession.refresh() }
                    } onSignOut: {
                        Task { await authManager.signOut() }
                    }
                } else {
                    SchoolWelcomeView()
                }
            }
        }
        .task {
            await authManager.getAuthState()
        }
        .task(id: authManager.authState) {
            switch authManager.authState {
            case .authenticated:
                await appSession.refresh()
            case .notAuthenticated:
                appSession.clear()
            case .notDetermind:
                break
            }
        }
    }
}

private extension SchoolRole {
    var usesAccessChecklist: Bool {
        self == .parent || self == .schoolDirector
    }
}

private struct AccessChecklistGateView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager

    @State private var items: [AccessChecklistItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingSignOutConfirmation = false

    private var isComplete: Bool {
        !items.isEmpty && items.allSatisfy { $0.status.satisfiesRequirement }
    }

    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    AppConstants.Colors.background.ignoresSafeArea()
                    ProgressView("Loading checklist")
                        .tint(AppConstants.Colors.accessibleYellow)
                        .foregroundColor(.white)
                }
            } else if isComplete {
                MainTabView()
            } else {
                NavigationStack {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                header
                                assignedWorkShortcut
                                checklist
                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding()
                        }

                        if showingSignOutConfirmation {
                            SignOutConfirmationOverlay(
                                message: "Your checklist progress is saved. You can continue after signing in again.",
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
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showingSignOutConfirmation = true
                            } label: {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            .foregroundColor(.white.opacity(0.82))
                        }
                    }
                    .refreshable { await load() }
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setup Checklist")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text(appSession.activeSchool?.name ?? "FireflyFM")
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text("Complete each accepted setup task to unlock the full app workspace.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.68))
        }
    }

    private var checklist: some View {
        VStack(spacing: 10) {
            ForEach(items) { item in
                NavigationLink {
                    item.destination
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.status.icon)
                            .font(.title3)
                            .foregroundColor(item.status.color)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(item.status.title)
                                    .font(.caption.bold())
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(item.status.color)
                                    .clipShape(Capsule())
                            }
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.62))
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding()
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var assignedWorkShortcut: some View {
        NavigationLink {
            AssignmentsView(surface: .all)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.title3)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assigned Work")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Open assignments, submit work, and respond to feedback while setup is in progress.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.42))
            }
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func load() async {
        guard let schoolId = appSession.activeSchool?.id, let role = appSession.role else {
            items = []
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let userId = try await ProfileService.shared.currentUserId()
            async let requirementsTask = SchoolWorkflowService.shared.fetchOnboardingRequirements(schoolId: schoolId)
            async let submissionsTask = SchoolWorkflowService.shared.fetchDocumentSubmissions(schoolId: schoolId)

            let requirements = try await requirementsTask
            let submissions = try await submissionsTask
            let payments: [PaymentSetupRecord]
            if AppConstants.Features.paymentsEnabled {
                payments = try await SchoolWorkflowService.shared.fetchPaymentSetupRecords(schoolId: schoolId)
            } else {
                payments = []
            }
            let assignedRequirements = requirements.filter { requirement in
                requirement.targetUserId == userId
                || requirement.targetRole == role
                || (requirement.targetUserId == nil && requirement.targetRole == nil)
            }
            let userSubmissions = submissions.filter { $0.submittedBy == userId }
            let userPayments = payments.filter { $0.userId == userId }

            switch role {
            case .parent:
                let roster = try await SchoolWorkflowService.shared.fetchChildRoster(schoolId: schoolId)
                items = parentItems(roster: roster, requirements: assignedRequirements, submissions: userSubmissions, payments: userPayments)
            case .schoolDirector:
                items = directorItems(requirements: assignedRequirements, submissions: userSubmissions, payments: userPayments)
            case .teacher, .hqDirector:
                items = []
            }
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load checklist", error)
            isLoading = false
        }
    }

    private func parentItems(
        roster: [ChildRosterItem],
        requirements: [OnboardingRequirement],
        submissions: [DocumentSubmission],
        payments: [PaymentSetupRecord]
    ) -> [AccessChecklistItem] {
        let hasCompletedIntake = roster.contains { item in
            hasText(item.medicalProfile?.allergies)
            && hasText(item.medicalProfile?.immunizationStatus)
            && hasText(item.medicalProfile?.physicalStatus)
            && hasText(item.medicalProfile?.sleepHabits)
        }

        return [
            AccessChecklistItem(
                title: "Parent Profile",
                detail: "Add your display name and photo.",
                status: hasText(appSession.profile?.displayName) ? .accepted : .notStarted,
                destination: AnyView(ProfileView())
            ),
            AccessChecklistItem(
                title: "Tuition Setup",
                detail: AppConstants.Features.paymentsEnabled
                    ? "Complete tuition setup and school review."
                    : "Waived for MVP testing until the payment-provider integration is enabled.",
                status: paymentStatus(payments, matching: "tuition"),
                destination: AnyView(PaymentsView())
            ),
            AccessChecklistItem(
                title: "Child Profile",
                detail: "Create each child who attends this school.",
                status: roster.isEmpty ? .notStarted : .accepted,
                destination: AnyView(ChildrenView())
            ),
            AccessChecklistItem(
                title: "Child Intake Form",
                detail: "Submit allergies, immunization, physical, sleep, dietary, and emergency details.",
                status: hasCompletedIntake ? .accepted : .notStarted,
                destination: AnyView(ChildrenView())
            ),
            AccessChecklistItem(
                title: "Required Documents",
                detail: "Submit assigned documents and wait for director review.",
                status: documentStatus(requirements: requirements, submissions: submissions),
                destination: AnyView(DocumentFeedbackLoopView())
            )
        ]
    }

    private func directorItems(
        requirements: [OnboardingRequirement],
        submissions: [DocumentSubmission],
        payments: [PaymentSetupRecord]
    ) -> [AccessChecklistItem] {
        [
            AccessChecklistItem(
                title: "School Access",
                detail: "Your director invite is linked to this school.",
                status: appSession.activeSchool == nil ? .notStarted : .accepted,
                destination: AnyView(SchoolWelcomeView())
            ),
            AccessChecklistItem(
                title: "Director Profile",
                detail: "Add your display name and photo.",
                status: hasText(appSession.profile?.displayName) ? .accepted : .notStarted,
                destination: AnyView(ProfileView())
            ),
            AccessChecklistItem(
                title: "Director Payment Setup",
                detail: AppConstants.Features.paymentsEnabled
                    ? "Complete payment setup and HQ review."
                    : "Waived for MVP testing until the payment-provider integration is enabled.",
                status: paymentStatus(payments, matching: "director_payment"),
                destination: AnyView(PaymentsView())
            ),
            AccessChecklistItem(
                title: "EEC License and Certificates",
                detail: "Submit required school/director documents for HQ review.",
                status: documentStatus(requirements: requirements, submissions: submissions),
                destination: AnyView(DocumentFeedbackLoopView())
            )
        ]
    }

    private func documentStatus(requirements: [OnboardingRequirement], submissions: [DocumentSubmission]) -> AccessTaskStatus {
        guard requirements.isEmpty == false else { return .accepted }

        let submissionsByRequirement = Dictionary(grouping: submissions, by: \.requirementId)
        if requirements.allSatisfy({ requirement in
            submissionsByRequirement[requirement.id]?.contains { $0.status == "verified" } == true
        }) {
            return .accepted
        }
        if submissions.contains(where: { $0.status == "flagged" }) {
            return .rejected
        }
        if submissions.contains(where: { $0.status == "submitted" }) {
            return .inReview
        }
        return .notStarted
    }

    private func paymentStatus(_ records: [PaymentSetupRecord], matching keyword: String) -> AccessTaskStatus {
        guard AppConstants.Features.paymentsEnabled else { return .waived }

        let matchingRecords = records.filter { $0.paymentType.localizedCaseInsensitiveContains(keyword) }
        guard matchingRecords.isEmpty == false else { return .notStarted }
        if matchingRecords.contains(where: { ["verified", "sandbox_verified"].contains($0.status) }) { return .accepted }
        if matchingRecords.contains(where: { $0.status == "waived" }) { return .waived }
        if matchingRecords.contains(where: { $0.status == "flagged" }) { return .rejected }
        if matchingRecords.contains(where: { $0.status == "submitted" }) { return .inReview }
        return .draft
    }

    private func hasText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

private struct AccessChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let status: AccessTaskStatus
    let destination: AnyView
}

private enum AccessTaskStatus {
    case notStarted
    case draft
    case inReview
    case accepted
    case waived
    case rejected

    var satisfiesRequirement: Bool {
        self == .accepted || self == .waived
    }

    var title: String {
        switch self {
        case .notStarted: "Not Started"
        case .draft: "Draft"
        case .inReview: "In Review"
        case .accepted: "Accepted"
        case .waived: "Waived for MVP"
        case .rejected: "Needs Work"
        }
    }

    var icon: String {
        switch self {
        case .notStarted: "circle"
        case .draft: "pencil.circle.fill"
        case .inReview: "clock.fill"
        case .accepted: "checkmark.circle.fill"
        case .waived: "checkmark.seal.fill"
        case .rejected: "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: return .white.opacity(0.45)
        case .draft: return AppConstants.Colors.accessibleYellow
        case .inReview: return .orange
        case .accepted: return .green
        case .waived: return .cyan
        case .rejected: return .red
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
}

private struct SchoolAccessErrorView: View {
    var message: String
    var onRetry: () -> Void
    var onSignOut: () -> Void

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)

                Text("Could not load school access")
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))

                VStack(spacing: 12) {
                    Button(action: onRetry) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SchoolAccessPrimaryButtonStyle())

                    Button(action: onSignOut) {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SchoolAccessSecondaryButtonStyle())
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppConstants.Colors.card)
            .cornerRadius(12)
            .padding(24)
        }
    }
}

private struct SchoolAccessPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.accessibleYellow.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}

private struct SchoolAccessSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.1))
            .cornerRadius(8)
    }
}
