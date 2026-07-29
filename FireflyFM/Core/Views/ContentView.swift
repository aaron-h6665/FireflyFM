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
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
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
                            .tint(AppConstants.Colors.primaryAction)
                    }
                }
            case .notAuthenticated:
                NavigationStack {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        
                        // Decorative Glow
                        VStack {
                            Circle()
                                .fill(AppConstants.Colors.wingMist.opacity(0.45))
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
                                    Text("FireflyFM")
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .foregroundColor(AppConstants.Colors.primaryText)
                                    Text("Connecting directors, staff, and parents.")
                                        .font(.subheadline)
                                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.85)) // High contrast text
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
                                        .background(AppConstants.Colors.primaryAction)
                                        .foregroundColor(AppConstants.Colors.primaryActionText)
                                        .cornerRadius(12)
                                        .shadow(color: AppConstants.Colors.primaryAction.opacity(0.22), radius: 10, x: 0, y: 5)
                                }
                                
                                // Pushes to the Role Selection View
                                NavigationLink(destination: RoleSelectionView()) {
                                    Text("Create an Account")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(AppConstants.Colors.card)
                                        .foregroundColor(AppConstants.Colors.primaryText)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(AppConstants.Colors.separator, lineWidth: 1)
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
                                .foregroundColor(AppConstants.Colors.primaryText)
                        }
                    }
                } else if appSession.isLoading {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        ProgressView("Loading school")
                            .tint(AppConstants.Colors.accessibleYellow)
                            .foregroundColor(AppConstants.Colors.primaryText)
                    }
                } else if appSession.backendCompatibility == .updateRequired {
                    BackendUpdateRequiredView()
                } else if appSession.hasSchoolAccess {
                    if appSession.role?.usesAccessChecklist == true {
                        switch appSession.activeContext?.membership.accessState {
                        case "onboarding":
                            OnboardingAccessGateView()
                        case "full":
                            MainTabView()
                                .id(appSession.activeMembershipId)
                        default:
                            // Fail closed if the backend has not returned an
                            // authoritative per-membership access state.
                            OnboardingAccessGateView()
                        }
                    } else {
                        MainTabView()
                            .id(appSession.activeMembershipId)
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
                await ChatNotificationManager.shared.requestAuthorization()
                await ChatNotificationManager.shared.syncPendingDeviceToken()
            case .notAuthenticated:
                appSession.clear()
            case .notDetermind:
                break
            }
        }
        .sheet(item: membershipInviteBinding) { invite in
            InviteCoordinatorView(invite: invite)
                .interactiveDismissDisabled()
        }
    }

    private var membershipInviteBinding: Binding<PendingInvite?> {
        Binding(
            get: {
                authManager.authState == .authenticated
                    ? deepLinkManager.pendingMembershipInvite
                    : nil
            },
            set: { _ in }
        )
    }
}

private extension SchoolRole {
    var usesAccessChecklist: Bool {
        self == .parent || self == .teacher || self == .schoolDirector
    }
}

private struct BackendUpdateRequiredView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "server.rack")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Text("Backend update required")
                    .font(.title2.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text("FireflyFM needs the verified database migrations before school data can be loaded.")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("Check Again") { Task { await appSession.refresh() } }
                    .buttonStyle(.borderedProminent)
                Button("Sign Out") { Task { await authManager.signOut() } }
                    .buttonStyle(.bordered)
            }
            .padding(28)
        }
    }
}

private struct AccessChecklistGateView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager

    @State private var items: [AccessChecklistItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingSignOutConfirmation = false
    @State private var showingProfile = false
    @State private var showingCompleted = false

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
                        .foregroundColor(AppConstants.Colors.primaryText)
                }
            } else if isComplete {
                MainTabView()
                    .id(appSession.activeMembershipId)
            } else {
                NavigationStack {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                header
                                nextActionCard
                                checklist
                                assignedWorkShortcut
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
                            Menu {
                                Button("Profile", systemImage: "person.crop.circle") {
                                    showingProfile = true
                                }
                                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                    showingSignOutConfirmation = true
                                }
                            } label: {
                                Image(systemName: "person.crop.circle.fill")
                            }
                            .foregroundColor(AppConstants.Colors.primaryAction)
                        }
                    }
                    .refreshable { await load() }
                    .sheet(isPresented: $showingProfile) { ProfileView() }
                }
            }
        }
        .task(id: appSession.activeMembershipId) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to \(appSession.activeSchool?.name ?? "FireflyFM")")
                        .font(.title2.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("We’ll guide you one step at a time.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }
            }

            if appSession.canSwitchSchools {
                Picker("Active School", selection: Binding(
                    get: { appSession.activeMembershipId ?? appSession.memberships.first?.membership.id },
                    set: { membershipId in
                        if let membershipId {
                            appSession.switchActiveMembership(to: membershipId)
                        }
                    }
                )) {
                    ForEach(appSession.memberships) { context in
                        Text(context.school.name).tag(Optional(context.membership.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(AppConstants.Colors.primaryAction)
                .accessibilityHint("Changes the active school and reloads its onboarding checklist")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your progress").font(.subheadline.bold())
                    Spacer()
                    Text("\(completedItems.count) of \(items.count)").font(.caption.bold())
                }
                ProgressView(value: completionProgress)
                    .tint(AppConstants.Colors.brandNavy)
                Text("Items sent for review can take a little time. Your school will let you know if anything needs an update.")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.brandNavy.opacity(0.72))
            }
            .padding(16)
            .foregroundColor(AppConstants.Colors.brandNavy)
            .background(AppConstants.Colors.softGlow)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
        }
    }

    private var completionProgress: Double {
        guard items.isEmpty == false else { return 0 }
        return Double(completedItems.count) / Double(items.count)
    }

    private var completedItems: [AccessChecklistItem] {
        items.filter { $0.status.satisfiesRequirement }
    }

    private var remainingItems: [AccessChecklistItem] {
        items.filter { !$0.status.satisfiesRequirement }
    }

    @ViewBuilder
    private var nextActionCard: some View {
        if let next = remainingItems.first {
            NavigationLink {
                next.destination
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Your next step", systemImage: "sparkles")
                        .font(.caption.bold())
                        .textCase(.uppercase)
                    Text(next.title)
                        .font(.title3.bold())
                    Text(next.detail)
                        .font(.subheadline)
                        .opacity(0.78)
                    Label("Continue", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.bold())
                }
                .foregroundColor(AppConstants.Colors.brandNavy)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppConstants.Colors.fireflyGlow)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            if remainingItems.count > 1 {
                Text("Coming up")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                ForEach(Array(remainingItems.dropFirst())) { item in
                    checklistRow(item)
                }
            }

            if completedItems.isEmpty == false {
                DisclosureGroup(isExpanded: $showingCompleted) {
                    VStack(spacing: 10) {
                        ForEach(completedItems) { item in checklistRow(item) }
                    }
                    .padding(.top, 10)
                } label: {
                    Label("Completed (\(completedItems.count))", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.primaryText)
                }
                .tint(AppConstants.Colors.primaryAction)
            }
        }
    }

    private func checklistRow(_ item: AccessChecklistItem) -> some View {
        NavigationLink {
            item.destination
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.status.icon)
                    .font(.title3)
                    .foregroundColor(item.status.color)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.title)
                            .font(.headline)
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Spacer()
                        Text(item.status.title)
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                    }
                    Text(item.detail)
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding()
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var assignedWorkShortcut: some View {
        NavigationLink {
            AssignmentsView(filter: .all)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.title3)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assigned Work")
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("Open assignments, submit work, and respond to feedback while setup is in progress.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.42))
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
        case .notStarted: "Ready to start"
        case .draft: "In progress"
        case .inReview: "With your school"
        case .accepted: "All set"
        case .waived: "Not required"
        case .rejected: "Update requested"
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
        case .notStarted: return AppConstants.Colors.secondaryText
        case .draft: return AppConstants.Colors.fireflyBlue
        case .inReview: return AppConstants.Colors.aqua
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
                    .foregroundColor(AppConstants.Colors.primaryText)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.75))

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
            .foregroundColor(AppConstants.Colors.primaryActionText)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.primaryAction.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}

private struct SchoolAccessSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(AppConstants.Colors.primaryText)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.1))
            .cornerRadius(8)
    }
}
