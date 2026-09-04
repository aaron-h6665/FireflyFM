import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct OnboardingManagementView: View {
    let school: School
    let mode: OnboardingManagementMode

    @State private var selectedRole: SchoolRole
    @State private var model = OnboardingManagementModel()
    @State private var showingInvite = false
    @State private var showingHelp = false

    init(school: School, mode: OnboardingManagementMode) {
        self.school = school
        self.mode = mode
        _selectedRole = State(initialValue: mode.initialRole)
    }

    private var availableRoles: [SchoolRole] {
        mode.availableRoles
    }

    private var roleTitle: String {
        selectedRole.onboardingManagementTitle
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    rolePicker
                    formSummary
                    actionGrid
                    progressSummary
                    helpCard
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            .refreshable { await load() }
        }
        .navigationTitle("Onboarding")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedRole) { await load() }
        .sheet(isPresented: $showingInvite) {
            if mode.usesHQInvitationFlow {
                HQDirectorInviteSheet(school: school) {
                    Task { await load() }
                }
            } else {
                OnboardingMemberInviteSheet(school: school, role: selectedRole) {
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            OnboardingHelpView(audience: .manager, role: selectedRole)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(school.name)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text(roleTitle)
                .font(.largeTitle.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text("Guide families through the required onboarding steps before the rest of the school workspace unlocks.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
        }
    }

    @ViewBuilder
    private var rolePicker: some View {
        if availableRoles.count > 1 {
            Picker("Role", selection: $selectedRole) {
                Text("Parents").tag(SchoolRole.parent)
                Text("Teachers").tag(SchoolRole.teacher)
            }
            .pickerStyle(.segmented)
        }
    }

    private var formSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Parent Google Form", systemImage: "list.clipboard.fill")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                statusBadge
            }
            Text("Parent intake is managed through one connected Google Form")
                .font(.title3.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text("Families submit child information and required documents through the form. FireflyFM imports responses for review.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private var statusBadge: some View {
        Text(model.parentFormConnected ? "Form connected" : "Form setup needed")
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.brandNavy)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(templateStatusColor)
            .clipShape(Capsule())
    }

    private var templateStatusColor: Color {
        model.parentFormConnected ? .green : .orange
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink {
                GoogleFormOnboardingView(school: school)
            } label: {
                actionCard("Manage Parent Form", icon: "list.clipboard.fill")
            }
            .buttonStyle(.plain)

            NavigationLink {
                OnboardingRecipientPreviewView(school: school, role: selectedRole, bundle: model.bundle)
            } label: {
                actionCard("Preview Onboarding", icon: "eye.fill")
            }
            .buttonStyle(.plain)

            Button {
                showingInvite = true
            } label: {
                actionCard("Generate Invite Code", icon: "person.badge.key.fill")
            }
            .buttonStyle(.plain)
            .disabled(model.parentFormConnected == false)

            NavigationLink {
                GoogleFormReviewView(school: school)
            } label: {
                actionCard("Review Form Responses", icon: "tray.full.fill", badge: model.progress.needsReviewCount)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionCard(_ title: String, icon: String, badge: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.brandNavy)
                        .padding(6)
                        .background(.orange)
                        .clipShape(Circle())
                }
            }
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            HStack(spacing: 10) {
                metric("Invited", value: model.progress.memberCount, color: AppConstants.Colors.primaryText)
                metric("In Setup", value: model.progress.onboardingCount, color: .orange)
                metric("Full Access", value: model.progress.fullCount, color: .green)
            }
        }
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private var helpCard: some View {
        Button {
            showingHelp = true
        } label: {
            HStack {
                Label("How Parent Forms Work", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.bold())
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundColor(AppConstants.Colors.primaryText)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func load() async {
        await model.load(schoolId: school.id, role: selectedRole)
    }
}

struct OnboardingTemplateBuilderView: View {
    let school: School
    let role: SchoolRole

    @State private var model = OnboardingTemplateBuilderModel()
    @State private var editorContext: RequirementEditorContext?
    @State private var showingHelp = false
    @State private var showingArchiveConfirmation = false

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            List {
                Section {
                    templateHeader
                }
                .listRowBackground(AppConstants.Colors.card)

                Section("Requirements") {
                    if model.isLoading {
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    } else if model.bundle.requirements.isEmpty {
                        emptyTemplate
                    } else {
                        ForEach(model.bundle.requirements) { requirement in
                            requirementRow(requirement)
                        }
                        .onMove(perform: moveRequirements)
                    }
                }
                .listRowBackground(AppConstants.Colors.card)

                Section {
                    Button {
                        prepareEditor(for: nil)
                    } label: {
                        Label("Add Requirement", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isSaving)

                    if let template = model.bundle.template, template.status == .draft {
                        Button {
                            publish(template)
                        } label: {
                            Label("Publish Changes", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(model.bundle.requirements.isEmpty || model.isSaving)
                    }

                    NavigationLink {
                        OnboardingRecipientPreviewView(school: school, role: role, bundle: model.bundle)
                    } label: {
                        Label("Preview as Recipient", systemImage: "eye.fill")
                    }
                    .disabled(model.bundle.requirements.isEmpty)
                }
                .listRowBackground(AppConstants.Colors.card)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .listRowBackground(AppConstants.Colors.card)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(roleTemplateTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if model.bundle.template?.status == .draft, model.bundle.requirements.count > 1 {
                    EditButton()
                }
                Menu {
                    Button { showingHelp = true } label: {
                        Label("How Parent Forms Work", systemImage: "questionmark.circle")
                    }
                    if model.bundle.template != nil {
                        Button(role: .destructive) { showingArchiveConfirmation = true } label: {
                            Label(
                                model.bundle.template?.status == .draft ? "Delete Draft" : "Archive Template",
                                systemImage: model.bundle.template?.status == .draft ? "trash" : "archivebox"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .sheet(item: $editorContext) { context in
            if let template = model.bundle.template {
                OnboardingRequirementEditorView(
                    school: school,
                    role: role,
                    template: template,
                    requirement: context.requirement,
                    attachments: context.requirement.map { model.bundle.attachments(for: $0.id) } ?? [],
                    position: context.requirement?.position ?? model.bundle.requirements.count
                ) {
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            OnboardingHelpView(audience: .manager, role: role)
        }
        .confirmationDialog(
            model.bundle.template?.status == .draft ? "Delete this unused draft?" : "Archive this template?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                model.bundle.template?.status == .draft ? "Delete Draft" : "Archive Template",
                role: .destructive
            ) { removeTemplate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.bundle.template?.status == .draft
                 ? "This draft has never been assigned. Its requirements will be permanently removed; the last published version stays available."
                 : "Existing onboarding stays intact. New invitations are paused until another version is published.")
        }
        .safeAreaInset(edge: .bottom) {
            if model.lastDeleted != nil {
                HStack {
                    Text("Requirement removed")
                        .font(.subheadline)
                    Spacer()
                    Button("Undo") { undoDelete() }
                        .fontWeight(.bold)
                }
                .foregroundColor(AppConstants.Colors.primaryText)
                .padding()
                .background(AppConstants.Colors.card)
            }
        }
    }

    private var roleTemplateTitle: String {
        role.onboardingTemplateTitle
    }

    private var templateHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.bundle.template?.name ?? roleTemplateTitle)
                    .font(.title2.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text(model.bundle.template?.status.title ?? "Not Created")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(model.bundle.template?.status == .published ? .green : .orange)
                    .clipShape(Capsule())
            }
            Text("Add a title, instructions, and any paperwork. FireflyFM handles assignment, review, feedback, and access automatically.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
            if let version = model.bundle.template?.version {
                Text("Version \(version) · Published edits become a new draft for future invitees.")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.5))
            }
        }
        .padding(.vertical, 6)
    }

    private var emptyTemplate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Start with one requirement", systemImage: "sparkles")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text("Example: “Signed enrollment agreement” with instructions and a PDF attached.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
            Button("Use This Example") {
                prepareEditor(for: nil)
            }
            .buttonStyle(.bordered)
            .tint(AppConstants.Colors.accessibleYellow)
        }
        .padding(.vertical, 8)
    }

    private func requirementRow(_ requirement: OnboardingTemplateRequirement) -> some View {
        Button {
            prepareEditor(for: requirement)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(requirement.position + 1)")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .frame(width: 26, height: 26)
                    .background(AppConstants.Colors.accessibleYellow)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(requirement.title)
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.primaryText)
                    if let description = requirement.description, description.isEmpty == false {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Label("\(model.bundle.attachments(for: requirement.id).count)", systemImage: "paperclip")
                        if role.supportsChildSpecificOnboarding {
                            Text(requirement.subjectScope.title)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.48))
                }
                Spacer()
                Menu {
                    Button { prepareEditor(for: requirement) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button { duplicate(requirement) } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) { remove(requirement) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                        .padding(8)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func prepareEditor(for original: OnboardingTemplateRequirement?) {
        Task {
            if await model.prepareDraft(schoolId: school.id, role: role) != nil {
                let mapped = original.flatMap(model.mappedRequirement)
                editorContext = RequirementEditorContext(requirement: mapped)
            }
        }
    }

    private func duplicate(_ original: OnboardingTemplateRequirement) {
        Task { await model.duplicate(original, schoolId: school.id, role: role) }
    }

    private func remove(_ original: OnboardingTemplateRequirement) {
        Task { await model.remove(original, schoolId: school.id, role: role) }
    }

    private func undoDelete() {
        Task { await model.undoDelete(schoolId: school.id, role: role) }
    }

    private func moveRequirements(from source: IndexSet, to destination: Int) {
        guard let template = model.bundle.template, template.status == .draft else { return }
        var reordered = model.bundle.requirements
        reordered.move(fromOffsets: source, toOffset: destination)
        Task {
            await model.reorder(
                reordered,
                templateId: template.id,
                schoolId: school.id,
                role: role
            )
        }
    }

    private func publish(_ template: OnboardingTemplate) {
        Task { await model.publish(templateId: template.id, schoolId: school.id, role: role) }
    }

    private func removeTemplate() {
        guard let template = model.bundle.template else { return }
        Task { await model.removeTemplate(template, schoolId: school.id, role: role) }
    }

    @MainActor
    private func load() async {
        await model.load(schoolId: school.id, role: role)
    }
}

private struct RequirementEditorContext: Identifiable {
    let id = UUID()
    let requirement: OnboardingTemplateRequirement?
}

private struct OnboardingRequirementEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    let role: SchoolRole
    let template: OnboardingTemplate
    let requirement: OnboardingTemplateRequirement?
    let position: Int
    var onSaved: () -> Void

    @State private var model = OnboardingRequirementEditorModel()
    @State private var title: String
    @State private var instructions: String
    @State private var subjectScope: OnboardingSubjectScope
    @State private var blocksAccess: Bool
    @State private var childRecordBinding: ChildRequirementBinding
    @State private var retainedAttachments: [OnboardingTemplateAttachment]
    @State private var selectedFileURLs: [URL] = []
    @State private var editorId = UUID()
    @State private var showingImporter = false
    @State private var fileSelectionError: String?

    init(
        school: School,
        role: SchoolRole,
        template: OnboardingTemplate,
        requirement: OnboardingTemplateRequirement?,
        attachments: [OnboardingTemplateAttachment],
        position: Int,
        onSaved: @escaping () -> Void
    ) {
        self.school = school
        self.role = role
        self.template = template
        self.requirement = requirement
        self.position = position
        self.onSaved = onSaved
        _title = State(initialValue: requirement?.title ?? "")
        _instructions = State(initialValue: requirement?.description ?? "")
        _subjectScope = State(initialValue: requirement?.subjectScope ?? .member)
        _blocksAccess = State(initialValue: requirement?.blocksAccess ?? true)
        _childRecordBinding = State(initialValue: requirement?.childRecordBinding ?? .none)
        _retainedAttachments = State(initialValue: attachments)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Requirement") {
                    TextField("Title (for example, Signed enrollment agreement)", text: $title)
                    TextField("Description or instructions (optional)", text: $instructions, axis: .vertical)
                        .lineLimit(4...8)
                }

                if role.supportsChildSpecificOnboarding {
                    Section("Applies To") {
                        Picker("Who completes this?", selection: $subjectScope) {
                            Text("Parent").tag(OnboardingSubjectScope.member)
                            Text("Each Child").tag(OnboardingSubjectScope.child)
                        }
                        .pickerStyle(.segmented)
                        Text(subjectScope == .child
                             ? "A separate requirement is created for every child connected to the parent."
                             : "This requirement is completed once by the parent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Access and child record") {
                        Toggle("Blocks app access until approved", isOn: $blocksAccess)
                            .disabled(position == 0)
                        if position == 0 {
                            Text("The core identity requirement is always blocking.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if subjectScope == .child {
                            Picker("Approved information", selection: $childRecordBinding) {
                                Text("Evidence only").tag(ChildRequirementBinding.none)
                                Text("Child document").tag(ChildRequirementBinding.childDocument)
                                Text("Immunization record").tag(ChildRequirementBinding.immunizationRecord)
                                Text("Medical clearance").tag(ChildRequirementBinding.medicalClearance)
                                Text("Medication authorization").tag(ChildRequirementBinding.medicationAuthorization)
                                Text("Emergency information").tag(ChildRequirementBinding.emergencyInformation)
                                Text("Consent").tag(ChildRequirementBinding.consent)
                            }
                            Text("The approved upload remains the evidence. Structured answers update the linked child record without another upload.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Paperwork (Optional)") {
                    ForEach(retainedAttachments) { attachment in
                        HStack {
                            Label(attachment.fileName, systemImage: "doc.fill")
                            Spacer()
                            Button("Remove") {
                                retainedAttachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    ForEach(selectedFileURLs, id: \.self) { url in
                        HStack {
                            Label(url.lastPathComponent, systemImage: "paperclip")
                            Spacer()
                            Button("Remove") { selectedFileURLs.removeAll { $0 == url } }
                        }
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Add Paperwork", systemImage: "paperclip")
                    }
                    Text("Recipients download these files, upload completed paperwork or a supporting file, and receive feedback here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = model.errorMessage ?? fileSelectionError {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(requirement == nil ? "Add Requirement" : "Edit Requirement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "Saving" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                do {
                    let urls = try result.get()
                    selectedFileURLs.append(contentsOf: urls.filter { selectedFileURLs.contains($0) == false })
                } catch {
                    fileSelectionError = "The selected paperwork could not be opened."
                }
            }
            .onChange(of: subjectScope) { _, newValue in
                if newValue != .child { childRecordBinding = .none }
            }
        }
    }

    private func save() {
        Task {
            let retained = retainedAttachments.map {
                OnboardingAttachmentDescriptor(
                    privateFilePath: $0.privateFilePath,
                    fileName: $0.fileName,
                    contentType: $0.contentType
                )
            }
            if await model.save(
                request: OnboardingRequirementSaveRequest(
                    templateId: template.id,
                    requirementId: requirement?.id,
                    title: title,
                    description: instructions,
                    subjectScope: role.supportsChildSpecificOnboarding ? subjectScope : .member,
                    position: position,
                    attachments: retained,
                    blocksAccess: position == 0 ? true : blocksAccess,
                    childRecordBinding: subjectScope == .child ? childRecordBinding : .none
                ),
                schoolId: school.id,
                editorId: editorId,
                selectedFileURLs: selectedFileURLs
            ) {
                onSaved()
                dismiss()
            }
        }
    }
}

struct OnboardingRecipientPreviewView: View {
    let school: School
    let role: SchoolRole
    let bundle: OnboardingTemplateBundle

    private let cards: [(String, String, String, String)] = [
        ("Invitation", "Parent invitation is ready", "Invite sent", "envelope.badge.fill"),
        ("Child connection", "Connect or create the child profile", "Ready", "figure.child"),
        ("Parent Intake form", "Complete child, health, contact, medicine, and document questions", "Not started", "list.clipboard.fill"),
        ("Response imported", "FireflyFM received the Google Form response", "Imported", "arrow.down.doc.fill"),
        ("Director review", "Review answers and uploaded documents", "Pending review", "doc.text.magnifyingglass"),
        ("Child record updated", "Approved information appears in the child record and Documents view", "Verified", "checkmark.seal.fill"),
        ("Access unlocked", "Required onboarding work is approved", "Complete", "lock.open.fill")
    ]

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewBanner
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Parent onboarding")
                            .font(.largeTitle.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text(school.name)
                            .font(.subheadline.bold())
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                        ProgressView(value: 1.0 / Double(cards.count))
                            .tint(.green)
                    }

                    ForEach(cards, id: \.0) { card in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: card.3)
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                Text(card.0)
                                    .font(.headline)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Spacer()
                                Text(card.2)
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                            }
                            Text(card.1)
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
                        }
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(10)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Recipient Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewBanner: some View {
        Label("Preview only — no real people, submissions, or files are changed.", systemImage: "eye.fill")
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.brandNavy)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppConstants.Colors.accessibleYellow)
            .cornerRadius(8)
    }

}

private struct RecipientFormStep: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let status: String
}

struct OnboardingAccessGateView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager

    @State private var model = OnboardingAccessGateModel()
    @State private var showingHelp = false
    @State private var showingSignOutConfirmation = false

    private var completedCount: Int {
        model.items.filter { ["approved", "waived"].contains($0.status) }.count
    }

    private var hasAttentionNeeded: Bool {
        model.items.contains { ["changes_requested", "overdue"].contains($0.status) }
    }

    private var isApproved: Bool {
        !model.items.isEmpty && completedCount == model.items.count
    }

    private var recipientSteps: [RecipientFormStep] {
        let isTeacher = (appSession.role ?? .parent) == .teacher
        var steps = [
            RecipientFormStep(id: "invitation", icon: "envelope.fill", title: "Invitation", description: "Your school invitation is connected to this account.", status: model.items.isEmpty ? "Connected" : "Complete")
        ]
        if isTeacher == false {
            steps.append(RecipientFormStep(id: "child", icon: "figure.child", title: "Child connection", description: "Connect or create the child profile this onboarding belongs to.", status: childConnectionStatus))
        }
        steps.append(contentsOf: [
            RecipientFormStep(id: "form", icon: "doc.text.fill", title: isTeacher ? "Teacher onboarding form" : "Parent Intake form", description: isTeacher ? "Complete the school’s onboarding form when it is available." : "Share child, medical, emergency-contact, and document information.", status: formStatus),
            RecipientFormStep(id: "import", icon: "arrow.down.doc.fill", title: "Response imported", description: "FireflyFM brings form answers and uploaded documents into review.", status: responseStatus),
            RecipientFormStep(id: "review", icon: "checkmark.seal.fill", title: "School review", description: "A director verifies the submitted information and documents.", status: reviewStatus),
            RecipientFormStep(id: "record", icon: "person.text.rectangle.fill", title: isTeacher ? "Profile and documents updated" : "Record and documents updated", description: isTeacher ? "Approved answers appear in your staff profile and Documents view." : "Approved answers appear in the child record and Documents view.", status: isApproved ? "Complete" : "Waiting"),
            RecipientFormStep(id: "access", icon: "lock.open.fill", title: "Access unlocked", description: "Required onboarding approval unlocks the rest of FireflyFM.", status: isApproved ? "Complete" : "Locked")
        ])
        return steps
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if model.isLoading {
                            ProgressView("Loading setup")
                                .tint(AppConstants.Colors.accessibleYellow)
                                .foregroundColor(AppConstants.Colors.primaryText)
                        } else {
                            formSteps
                        }
                        Button {
                            showingHelp = true
                        } label: {
                            Label("Setup Help & Status Guide", systemImage: "questionmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppConstants.Colors.accessibleYellow)
                        if let errorMessage = model.errorMessage {
                            Text(errorMessage).font(.caption).foregroundColor(.red)
                        }
                    }
                    .padding()
                }
                .refreshable { await load() }

                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        message: "Your setup progress is saved. You can continue after signing in again.",
                        onCancel: { showingSignOutConfirmation = false },
                        onSignOut: {
                            showingSignOutConfirmation = false
                            Task { await authManager.signOut() }
                        }
                    )
                    .zIndex(2)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingSignOutConfirmation = true } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingHelp) {
            OnboardingHelpView(audience: .recipient, role: appSession.role ?? .parent)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setup Checklist")
                .font(.largeTitle.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(appSession.activeSchool?.name ?? "FireflyFM")
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text(onboardingSummary)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
            ProgressView(value: model.items.isEmpty ? 0 : Double(completedCount) / Double(model.items.count))
                .tint(.green)
        }
    }

    private var onboardingSummary: String {
        if hasAttentionNeeded { return "Your school requested an update" }
        if isApproved { return "Onboarding complete" }
        if model.items.isEmpty { return "Waiting for your school’s form setup" }
        return "Your form-based onboarding is in progress"
    }

    private var childConnectionStatus: String {
        if model.items.contains(where: { $0.assignmentId == nil && $0.subjectScope == .child }) { return "Needs your action" }
        if model.items.isEmpty { return "Not started" }
        return "Ready"
    }

    private var formStatus: String {
        if model.items.isEmpty { return "Waiting" }
        if hasAttentionNeeded { return "Changes requested" }
        if isApproved { return "Complete" }
        return "Ready to complete"
    }

    private var responseStatus: String {
        isApproved ? "Complete" : "Waiting"
    }

    private var reviewStatus: String {
        if hasAttentionNeeded { return "Needs your action" }
        if isApproved { return "Complete" }
        return model.items.isEmpty ? "Waiting" : "Waiting on school"
    }

    @ViewBuilder
    private var formSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Onboarding steps")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            ForEach(recipientSteps) { step in
                if step.id == "child" && childConnectionStatus == "Needs your action" {
                    NavigationLink { childConnectionDestination } label: {
                        formStepCard(step, isActionable: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    formStepCard(step, isActionable: false)
                }
            }
        }
    }

    private func formStepCard(_ step: RecipientFormStep, isActionable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: step.icon)
                .font(.headline)
                .foregroundColor(step.status == "Complete" ? .green : AppConstants.Colors.accessibleYellow)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(step.description)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(step.status)
                    .font(.caption.bold())
                    .foregroundColor(step.status == "Complete" ? .green : AppConstants.Colors.primaryText.opacity(0.58))
                if isActionable {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    @ViewBuilder
    private var childConnectionDestination: some View {
        if let school = appSession.activeSchool {
            ChildConnectionView(school: school) { Task { await load() } }
        } else {
            Text("School access is unavailable.")
        }
    }

    @MainActor
    private func load() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        if await model.load(schoolId: schoolId) { await appSession.refresh() }
    }
}

private struct OnboardingMemberInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    let role: SchoolRole
    var onInvited: () -> Void

    @State private var model = OnboardingMemberInviteModel()
    @State private var name = ""
    @State private var email = ""
    @State private var copiedCode = false

    var body: some View {
        NavigationStack {
            Form {
                Section("\(role.title) Invitation") {
                    TextField("Name (optional)", text: $name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("The generated code works only for this email address and expires after 14 days. The setup checklist is created only after the invitee signs in and accepts it.")
                        .font(.caption)
                }
                if let createdInvite = model.createdInvite, let code = createdInvite.token {
                    Section("Invitation Code") {
                        Text(code)
                            .font(.caption.monospaced().bold())
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = code
                            copiedCode = true
                        } label: {
                            Label(copiedCode ? "Code Copied" : "Copy Invitation Code", systemImage: copiedCode ? "checkmark" : "doc.on.doc")
                        }
                        if let inviteURL = createdInvite.inviteURL {
                            ShareLink(item: inviteURL) {
                                Label("Share Invitation Link", systemImage: "square.and.arrow.up")
                            }
                        }
                        Text("The invitee signs in, chooses Accept an Invitation, pastes this code, and confirms.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Copy it now. The same code cannot be displayed again after this screen closes.")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Invite \(role.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.createdInvite == nil ? "Cancel" : "Done") { dismiss() }
                }
                if model.createdInvite == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.isSaving ? "Generating" : "Generate Code") { createInvite() }
                            .disabled(email.contains("@") == false || model.isSaving)
                    }
                }
            }
        }
    }

    private func createInvite() {
        Task {
            if await model.create(.init(
                    schoolId: school.id,
                    email: email,
                    displayName: name,
                    role: role
                )) {
                onInvited()
            }
        }
    }
}

enum OnboardingHelpAudience: Equatable {
    case manager
    case recipient
}

struct OnboardingHelpView: View {
    @Environment(\.dismiss) private var dismiss
    let audience: OnboardingHelpAudience
    let role: SchoolRole

    var body: some View {
        NavigationStack {
            List {
                if audience == .manager {
                    helpSection("Requirements are automatic", "Every published item is assigned to future \(role.title.lowercased()) invitees and blocks full access until approved or waived.", icon: "wand.and.stars")
                    helpSection("Review is already assigned", role.onboardingManagerReviewHelp, icon: "person.badge.shield.checkmark")
                    helpSection("Published changes are safe", "Editing creates a draft for future invitees. People already in setup keep the version they received.", icon: "clock.arrow.circlepath")
                    helpSection("Delete drafts; archive published work", "An unused draft can be deleted. Once published, the template remains in the audit history and can only be archived, which pauses new invitations without changing existing work.", icon: "archivebox")
                    if role.supportsChildSpecificOnboarding {
                        helpSection("Parent or Each Child", "Parent requirements happen once. Each Child creates separate work for every connected child, shared by authorized guardians.", icon: "figure.2.and.child.holdinghands")
                    }
                } else {
                    helpSection("Complete your form", "Open the school’s Google Form and provide the requested information and documents. FireflyFM imports the response for review.", icon: "doc.text.fill")
                    helpSection("Waiting on review", "Your form response is with the authorized school reviewer. You do not need to submit it again unless changes are requested.", icon: "clock.fill")
                    helpSection("Changes requested", "Read the reviewer note, correct the Google Form response, and submit it again when your school asks.", icon: "arrow.uturn.backward.circle")
                    helpSection("Private paperwork", "Imported files use private storage and short-lived links. Only authorized people can open them.", icon: "lock.shield.fill")
                    helpSection("File help", "FireflyFM accepts files up to \(UploadPolicy.maxFileSizeDescription). If an upload fails, confirm the file is available on this device and try again.", icon: "doc.badge.ellipsis")
                }
            }
            .navigationTitle(audience == .manager ? "How Parent Forms Work" : "Setup Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func helpSection(_ title: String, _ body: String, icon: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

private func onboardingStatusTitle(_ status: String) -> String {
    switch status {
    case "not_started": "Not Started"
    case "in_progress": "In Progress"
    case "in_review": "In Review"
    case "changes_requested": "Changes Requested"
    case "approved": "Approved"
    case "waived": "Waived"
    case "overdue": "Overdue"
    default: status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func onboardingStatusIcon(_ status: String) -> String {
    switch status {
    case "not_started": "circle"
    case "in_progress": "pencil.circle.fill"
    case "in_review": "clock.fill"
    case "changes_requested": "exclamationmark.circle.fill"
    case "approved": "checkmark.circle.fill"
    case "waived": "checkmark.seal.fill"
    case "overdue": "calendar.badge.exclamationmark"
    default: "circle"
    }
}

private func onboardingStatusColor(_ status: String) -> Color {
    switch status {
    case "not_started": AppConstants.Colors.secondaryText
    case "in_progress": AppConstants.Colors.accessibleYellow
    case "in_review": .orange
    case "changes_requested", "overdue": .red
    case "approved": .green
    case "waived": .cyan
    default: AppConstants.Colors.secondaryText
    }
}
