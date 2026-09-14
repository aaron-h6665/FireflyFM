import SwiftUI
import Observation

enum PaperworkArchiveFilter: String, CaseIterable, Identifiable {
    case active
    case archived

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor
@Observable
final class PaperworkWorkspaceModel {
    private(set) var requests: [PaperworkAssignment] = []
    private(set) var submissions: [PaperworkSubmission] = []
    private(set) var schools: [School] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(schoolId: UUID?, crossSchool: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if crossSchool && schools.isEmpty {
                schools = try await SchoolService.shared.fetchSchoolsForHQ()
            }
            guard let schoolId else {
                requests = []
                submissions = []
                return
            }
            async let loadedRequests = SchoolWorkflowService.shared.fetchPaperworkAssignments(schoolId: schoolId)
            async let loadedSubmissions = SchoolWorkflowService.shared.fetchPaperworkSubmissions(schoolId: schoolId)
            (requests, submissions) = try await (loadedRequests, loadedSubmissions)
        } catch where AppErrorMessage.isCancellation(error) {} catch {
            errorMessage = AppErrorMessage.school("Could not load paperwork", error)
        }
    }
}

struct PaperworkWorkspaceView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var model = PaperworkWorkspaceModel()
    @State private var archiveFilter: PaperworkArchiveFilter = .active
    @State private var selectedSchoolId: UUID?

    private var policy: PaperworkAccessPolicy {
        PaperworkAccessPolicy(context: appSession.accessContext(selectedSchoolId: selectedSchoolId))
    }

    private var effectiveSchoolId: UUID? {
        selectedSchoolId ?? appSession.activeSchool?.id
    }

    private var selectedSchool: School? {
        if let selectedSchoolId {
            return model.schools.first { $0.id == selectedSchoolId }
        }
        return appSession.activeSchool
    }

    private var visibleRequests: [PaperworkAssignment] {
        model.requests.filter { request in
            (archiveFilter == .archived) == (request.status == "archived")
        }
    }

    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)

                    schoolPicker
                    onboardingSection

                    Picker("Paperwork view", selection: $archiveFilter) {
                        ForEach(PaperworkArchiveFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("paperwork-archive-filter")

                    Text("Other Paperwork")
                        .font(.title3.bold())

                    if model.isLoading && model.requests.isEmpty {
                        ProgressView("Loading paperwork…")
                    } else if visibleRequests.isEmpty {
                        FireflyEmptyState(
                            title: archiveFilter == .active ? "No active paperwork" : "No archived paperwork",
                            message: archiveFilter == .active
                                ? "Forms, document requests, and acknowledgements will appear here."
                                : "Completed paperwork remains available here for your records.",
                            systemImage: "doc.text.fill"
                        )
                    } else {
                        FireflySectionCard {
                            ForEach(Array(visibleRequests.enumerated()), id: \.element.id) { index, request in
                                NavigationLink {
                                    PaperworkRequestDetailView(
                                        request: request,
                                        submissions: model.submissions.filter { $0.assignmentId == request.id },
                                        canReview: policy.canReview
                                    ) { Task { await reload() } }
                                } label: {
                                    paperworkRow(request)
                                }
                                .buttonStyle(.plain)
                                if index < visibleRequests.count - 1 { Divider() }
                            }
                        }
                    }

                    if let errorMessage = model.errorMessage {
                        FireflyInlineError(message: errorMessage)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Paperwork")
        .task(id: "\(appSession.activeMembershipId?.uuidString ?? "none")-\(selectedSchoolId?.uuidString ?? "active")") {
            await reload()
        }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private var schoolPicker: some View {
        if policy.canSelectSchool && !model.schools.isEmpty {
            Picker("School", selection: Binding(
                get: { selectedSchoolId ?? appSession.activeSchool?.id },
                set: { selectedSchoolId = $0 }
            )) {
                ForEach(model.schools) { school in
                    Text(school.name).tag(Optional(school.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var onboardingSection: some View {
        if let school = selectedSchool {
            Text("Onboarding")
                .font(.title3.bold())
            if policy.canCreate {
                WorkspaceLink(
                    title: "Manage Onboarding Paperwork",
                    subtitle: "Configure Forms, documents, acknowledgements, and access requirements",
                    systemImage: "list.clipboard.fill",
                    destination: OnboardingManagementView(
                        school: school,
                        mode: appSession.role == .hqDirector ? .hqDirector : .schoolDirector
                    )
                )
                if appSession.role == .schoolDirector {
                    WorkspaceLink(
                        title: "Review Form Responses",
                        subtitle: "Review active responses and open completed history",
                        systemImage: "tray.full.fill",
                        destination: GoogleFormReviewView(school: school)
                    )
                }
            } else {
                WorkspaceLink(
                    title: "My Onboarding Paperwork",
                    subtitle: "Open Forms, continue drafts, and review feedback",
                    systemImage: "doc.text.fill",
                    destination: OnboardingAccessGateView(domain: .paperwork)
                )
            }
        }
    }

    private var description: String {
        switch appSession.role {
        case .parent: "Forms, child documents, acknowledgements, and school requests live here—not in Assignments."
        case .teacher: "Staff Forms, compliance documents, and acknowledgements live here."
        case .schoolDirector: "Create and review family and staff paperwork for this school."
        case .hqDirector: "Manage authorized paperwork across schools while each record keeps its school boundary."
        case .none: "School paperwork."
        }
    }

    private func paperworkRow(_ request: PaperworkAssignment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: request.requestKind == "acknowledgement" ? "checkmark.seal.fill" : "doc.fill")
                .foregroundStyle(request.status == "archived" ? .secondary : FireflyTheme.Colors.primaryAction)
            VStack(alignment: .leading, spacing: 3) {
                Text(request.title).font(.headline)
                if let description = request.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @MainActor
    private func reload() async {
        await model.load(schoolId: effectiveSchoolId, crossSchool: policy.canSelectSchool)
        if selectedSchoolId == nil, policy.canSelectSchool, appSession.activeSchool == nil {
            selectedSchoolId = model.schools.first?.id
        }
    }
}

private struct PaperworkRequestDetailView: View {
    let request: PaperworkAssignment
    let submissions: [PaperworkSubmission]
    let canReview: Bool
    let onChanged: () -> Void

    var body: some View {
        Form {
            Section("Request") {
                LabeledContent("Type", value: request.requestKind.replacingOccurrences(of: "_", with: " ").capitalized)
                if let description = request.description { Text(description) }
                if let dueAt = request.dueAt {
                    LabeledContent("Due", value: dueAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            Section("Submissions") {
                if submissions.isEmpty {
                    Text(request.requestKind == "acknowledgement" ? "Not acknowledged yet." : "No document has been submitted.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(submissions) { submission in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(submission.fileName ?? "Acknowledgement").font(.headline)
                            Text(submission.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if canReview {
                Section("Review") {
                    Text("Review decisions and feedback are preserved with each immutable attempt.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(request.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OnboardingLimitedWorkspaceView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingProfile = false
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            FireflyScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                        Text("Finish Setup")
                            .font(.largeTitle.bold())
                        Text("Your progress is saved. Complete paperwork and any payment requirement to unlock the rest of FireflyFM.")
                            .foregroundStyle(FireflyTheme.Colors.secondaryText)

                        WorkspaceLink(
                            title: "Paperwork",
                            subtitle: "Forms, documents, acknowledgements, and review feedback",
                            systemImage: "doc.text.fill",
                            destination: OnboardingAccessGateView(domain: .paperwork)
                        )
                        WorkspaceLink(
                            title: "Payments",
                            subtitle: "Required invoices, payment confirmation, and review status",
                            systemImage: "creditcard.fill",
                            destination: OnboardingAccessGateView(domain: .payments)
                        )
                    }
                    .padding()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingProfile = true } label: { Image(systemName: "person.crop.circle") }
                    Button { showingSignOutConfirmation = true } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                }
            }
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .overlay {
                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        message: "Your setup progress is saved.",
                        onCancel: { showingSignOutConfirmation = false },
                        onSignOut: {
                            showingSignOutConfirmation = false
                            Task { await authManager.signOut() }
                        }
                    )
                }
            }
        }
    }
}
