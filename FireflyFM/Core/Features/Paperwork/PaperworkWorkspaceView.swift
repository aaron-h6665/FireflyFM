import SwiftUI
import Supabase
import Observation
import UniformTypeIdentifiers

enum PaperworkArchiveFilter: String, CaseIterable, Identifiable {
    case active
    case archived

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor
@Observable
final class PaperworkWorkspaceModel {
    private(set) var items: [PaperworkItem] = []
    private(set) var schools: [School] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(schoolId: UUID?, crossSchool: Bool, archived: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if crossSchool && schools.isEmpty {
                schools = try await SchoolService.shared.fetchSchoolsForHQ()
            }
            guard let schoolId else {
                items = []
                return
            }
            items = try await SchoolWorkflowService.shared.fetchMyPaperworkItems(schoolId: schoolId, archived: archived)
        } catch where AppErrorMessage.isCancellation(error) {} catch {
            errorMessage = AppErrorMessage.school("Could not load paperwork", error)
        }
    }
}

struct LegacyPaperworkWorkspaceView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var model = PaperworkWorkspaceModel()
    @State private var archiveFilter: PaperworkArchiveFilter = .active
    @State private var selectedSchoolId: UUID?
    @State private var showingComposer = false

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

    private var visibleItems: [PaperworkItem] {
        var seen = Set<UUID>()
        return model.items.filter { seen.insert($0.itemId).inserted }
    }

    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)

                    schoolPicker
                    reviewQueueSection
                    onboardingPaperworkSection

                    Picker("Paperwork view", selection: $archiveFilter) {
                        ForEach(PaperworkArchiveFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("paperwork-archive-filter")

                    Text("Paperwork")
                        .font(.title3.bold())

                    if model.isLoading && model.items.isEmpty {
                        ProgressView("Loading paperwork…")
                    } else if visibleItems.isEmpty {
                        FireflyEmptyState(
                            title: archiveFilter == .active ? "No active paperwork" : "No archived paperwork",
                            message: archiveFilter == .active
                                ? "Forms, document requests, and acknowledgements will appear here."
                                : "Completed paperwork remains available here for your records.",
                            systemImage: "doc.text.fill"
                        )
                    } else {
                        FireflySectionCard {
                            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                NavigationLink {
                                    paperworkDestination(item)
                                } label: {
                                    paperworkRow(item)
                                }
                                .buttonStyle(.plain)
                                if index < visibleItems.count - 1 { Divider() }
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
        .toolbar {
            if policy.canCreate, effectiveSchoolId != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingComposer = true } label: { Label("New Paperwork", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            if let schoolId = effectiveSchoolId {
                PaperworkComposerView(schoolId: schoolId) { Task { await reload() } }
            }
        }
        .task(id: "\(appSession.activeMembershipId?.uuidString ?? "none")-\(selectedSchoolId?.uuidString ?? "active")-\(archiveFilter.rawValue)") {
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
    private var reviewQueueSection: some View {
        if let school = selectedSchool, policy.canReview {
            Text("Review Queue")
                .font(.title3.bold())
            WorkspaceLink(
                title: "Review Form Responses",
                subtitle: "Review active responses and open completed history",
                systemImage: "tray.full.fill",
                destination: GoogleFormReviewView(school: school)
            )
        }
    }

    @ViewBuilder
    private var onboardingPaperworkSection: some View {
        if !policy.canReview {
            Text("Onboarding")
                .font(.title3.bold())
            WorkspaceLink(
                title: "My Onboarding Paperwork",
                subtitle: "Open Forms, continue drafts, and review feedback",
                systemImage: "doc.text.fill",
                destination: OnboardingAccessGateView(domain: .paperwork)
            )
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

    @ViewBuilder
    private func paperworkDestination(_ item: PaperworkItem) -> some View {
        if item.sourceKind == .googleForm, let school = selectedSchool {
            if policy.canReview {
                GoogleFormReviewView(school: school)
            } else {
                OnboardingAccessGateView(domain: .paperwork)
            }
        } else if let requestId = item.nativeRequestId {
            LazyPaperworkRequestDetailView(
                requestId: requestId,
                canReview: policy.canReview
            ) { Task { await reload() } }
        } else {
            ContentUnavailableView("Paperwork unavailable", systemImage: "doc.text")
        }
    }

    private func paperworkRow(_ item: PaperworkItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.sourceKind == .googleForm ? "doc.text.fill" : item.sourceKind == .acknowledgement ? "checkmark.seal.fill" : "doc.fill")
                .foregroundStyle(archiveFilter == .archived ? .secondary : FireflyTheme.Colors.primaryAction)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                if let description = item.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(item.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @MainActor
    private func reload() async {
        await model.load(schoolId: effectiveSchoolId, crossSchool: policy.canSelectSchool, archived: archiveFilter == .archived)
        if selectedSchoolId == nil, policy.canSelectSchool, appSession.activeSchool == nil {
            selectedSchoolId = model.schools.first?.id
        }
    }
}

struct LazyPaperworkRequestDetailView: View {
    let requestId: UUID
    let canReview: Bool
    var recipientId: UUID? = nil
    let onChanged: () -> Void

    @State private var request: PaperworkAssignment?
    @State private var submissions: [PaperworkSubmission] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && request == nil {
                ProgressView("Loading paperwork…")
            } else if let request {
                PaperworkRequestDetailView(
                    request: request,
                    submissions: recipientId.map { recipient in submissions.filter { $0.submittedBy == recipient } } ?? submissions,
                    canReview: canReview
                ) {
                    onChanged()
                    Task { await load() }
                }
            } else {
                ContentUnavailableView {
                    Label("Paperwork Not Found", systemImage: "doc.text")
                } description: {
                    Text(errorMessage ?? "This paperwork request could not be loaded.")
                } actions: {
                    Button("Retry") {
                        Task { await load() }
                    }
                }
            }
        }
        .task(id: requestId) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let loadedRequest = SchoolWorkflowService.shared.fetchPaperworkAssignment(assignmentId: requestId)
            async let loadedSubmissions = SchoolWorkflowService.shared.fetchSubmissionsForAssignment(assignmentId: requestId)
            let (req, subs) = try await (loadedRequest, loadedSubmissions)
            request = req
            submissions = subs
        } catch where AppErrorMessage.isCancellation(error) {} catch {
            errorMessage = AppErrorMessage.school("Could not load paperwork details", error)
        }
    }
}

private struct PaperworkRequestDetailView: View {
    let request: PaperworkAssignment
    let submissions: [PaperworkSubmission]
    let canReview: Bool
    let onChanged: () -> Void
    @State private var showingImporter = false
    @State private var isSaving = false
    @State private var reviewMessage = ""
    @State private var corrections: [PaperworkCorrectionDraft] = []
    @State private var errorMessage: String?

    private var latestSubmissions: [PaperworkSubmission] {
        PaperworkSubmission.latestPerSubmitter(in: submissions)
    }

    private var canComplete: Bool {
        guard ["published", "closed"].contains(request.status) else { return false }
        guard let latestSubmission = latestSubmissions.first else { return true }
        return latestSubmission.status == "changes_requested"
    }

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
                            if let name = submission.fileName {
                                PaperworkFileButton(name: name, path: submission.filePath)
                            } else { Text("Acknowledgement").font(.headline) }
                            Text(submission.status.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                            if let note = submission.reviewerMessage ?? submission.flagReason { Text(note).font(.subheadline) }
                        }
                    }
                }
            }
            if AppConfiguration.workspaceBetaEnabled, let latest = latestSubmissions.first {
                CorrectionChecklist(googleImportId: nil, submissionId: latest.id)
            }
            if canReview {
                Section("Review") {
                    TextField("Feedback", text: $reviewMessage, axis: .vertical)
                    ForEach(latestSubmissions.filter { ["submitted", "resubmitted"].contains($0.status) }) { submission in
                        if AppConfiguration.workspaceBetaEnabled {
                            CorrectionTargetEditor(kind: "file", target: submission.id.uuidString, title: submission.fileName ?? "Acknowledgement", corrections: $corrections)
                        }
                        HStack {
                            Button("Request changes") { review(submission, decision: "changes_requested") }
                            Spacer()
                            Button("Accept") { review(submission, decision: "accepted") }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else if canComplete {
                Section("Complete") {
                    if request.requestKind == "acknowledgement" {
                        Button("Acknowledge") { acknowledge() }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving)
                    } else {
                        Button("Upload document") { showingImporter = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving)
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(request.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data, .pdf, .image], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { submit(url) }
            case .failure(let error):
                errorMessage = AppErrorMessage.school("Could not choose document", error)
            }
        }
    }

    private func acknowledge() {
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                _ = try await SchoolWorkflowService.shared.acknowledgePaperworkRequest(
                    id: request.id,
                    idempotencyKey: "ios:paperwork-ack:\(UUID().uuidString)"
                )
                onChanged()
            } catch { errorMessage = AppErrorMessage.school("Could not acknowledge paperwork", error) }
        }
    }

    private func submit(_ url: URL) {
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await SchoolWorkflowService.shared.submitPaperwork(assignment: request, fileURL: url)
                onChanged()
            } catch { errorMessage = AppErrorMessage.school("Could not submit paperwork", error) }
        }
    }

    private func review(_ submission: PaperworkSubmission, decision: String) {
        if decision == "changes_requested" && corrections.contains(where: {
            $0.target_id == submission.id.uuidString && $0.note.trimmed.isEmpty
        }) {
            errorMessage = "Add a note to each flagged file."
            return
        }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                if AppConfiguration.workspaceBetaEnabled {
                    let targets = decision == "changes_requested" ? corrections.filter { $0.target_id == submission.id.uuidString } : []
                    let message = ([reviewMessage] + targets.map { "\($0.title): \($0.note)" }).filter { !$0.isEmpty }.joined(separator: "\n")
                    _ = try await AppConstants.supabase.rpc("review_paperwork_with_corrections", params: NativeCorrectionReviewParams(
                        input_submission_id: submission.id, input_decision: decision, input_message: message.nilIfEmpty, input_corrections: targets
                    )).execute()
                } else {
                _ = try await SchoolWorkflowService.shared.reviewPaperworkSubmission(
                    id: submission.id,
                    decision: decision,
                    message: reviewMessage.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
                }
                onChanged()
            } catch { errorMessage = AppErrorMessage.school("Could not review paperwork", error) }
        }
    }
}

struct PaperworkComposerView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @Environment(\.dismiss) private var dismiss
    let schoolId: UUID
    let onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var requestKind = "document_upload"
    @State private var targetRole: SchoolRole = .parent
    @State private var selectedRecipientIds = Set<UUID>()
    @State private var members: [SchoolMember] = []
    @State private var children: [Child] = []
    @State private var isChildSpecific = false
    @State private var selectedChildId: UUID?
    @State private var hasDueDate = false
    @State private var dueAt = Date().addingTimeInterval(7 * 86_400)
    @State private var requiresReview = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var eligibleMembers: [SchoolMember] { members.filter { $0.membership.role == targetRole && $0.id != appSession.profile?.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    TextField("Title", text: $title)
                    TextField("Instructions", text: $description, axis: .vertical)
                    Picker("Type", selection: $requestKind) {
                        Text("Document upload").tag("document_upload")
                        Text("Acknowledgement").tag("acknowledgement")
                    }
                    Toggle("Requires review", isOn: $requiresReview)
                }
                Section("Recipients") {
                    Picker("Role", selection: $targetRole) {
                        Text("Parents").tag(SchoolRole.parent)
                        Text("Teachers").tag(SchoolRole.teacher)
                        if appSession.role == .hqDirector { Text("School directors").tag(SchoolRole.schoolDirector) }
                    }
                    ForEach(eligibleMembers) { member in
                        Toggle(member.displayName, isOn: Binding(
                            get: { selectedRecipientIds.contains(member.id) },
                            set: { selected in
                                if selected { selectedRecipientIds.insert(member.id) }
                                else { selectedRecipientIds.remove(member.id) }
                            }
                        ))
                    }
                    if targetRole == .parent && !children.isEmpty {
                        Toggle("For a specific child", isOn: $isChildSpecific)
                        if isChildSpecific {
                            Picker("Child", selection: $selectedChildId) {
                                Text("Choose a child").tag(Optional<UUID>.none)
                                ForEach(children) { child in Text(child.fullName).tag(Optional(child.id)) }
                            }
                        }
                    }
                }
                Section("Due date") {
                    Toggle("Set a due date", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("Due", selection: $dueAt, in: Date()...) }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("New Paperwork")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || selectedRecipientIds.isEmpty
                                  || (isChildSpecific && selectedChildId == nil)
                                  || isSaving)
                }
            }
            .task {
                if AppConfiguration.workspaceBetaEnabled && appSession.role == .hqDirector { targetRole = .schoolDirector }
                await load()
            }
            .onChange(of: targetRole) { _, _ in
                selectedRecipientIds.removeAll()
                isChildSpecific = false
                selectedChildId = nil
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            async let loadedMembers = SchoolService.shared.fetchMembers(schoolId: schoolId)
            async let loadedChildren = SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)
            (members, children) = try await (loadedMembers, loadedChildren)
        } catch { errorMessage = AppErrorMessage.school("Could not load recipients", error) }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                _ = try await SchoolWorkflowService.shared.createPaperworkRequest(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    requestKind: requestKind,
                    audienceRole: targetRole,
                    childId: isChildSpecific ? selectedChildId : nil,
                    recipientIds: Array(selectedRecipientIds),
                    dueAt: hasDueDate ? dueAt : nil,
                    requiresReview: requiresReview
                )
                onSaved()
                dismiss()
            } catch { errorMessage = AppErrorMessage.school("Could not create paperwork", error) }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct OnboardingLimitedWorkspaceView: View {
    var body: some View {
        OnboardingAccessGateView(domain: .all)
    }
}
