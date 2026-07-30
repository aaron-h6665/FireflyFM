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
                    templateSummary
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
            Text("Create the requirements people complete before the rest of the school workspace unlocks.")
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

    private var templateSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Template", systemImage: "doc.on.doc.fill")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                statusBadge
            }
            Text(model.bundle.template?.name ?? roleTitle)
                .font(.title3.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(model.bundle.requirements.isEmpty
                 ? "No requirements yet. Add the first requirement to begin."
                 : "\(model.bundle.requirements.count) requirement\(model.bundle.requirements.count == 1 ? "" : "s") · All requirements block full access.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
            if model.bundle.template?.status == .draft, model.bundle.template?.version ?? 1 > 1 {
                Label("These changes affect future invitees only.", systemImage: "person.crop.circle.badge.clock")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private var statusBadge: some View {
        Text(model.bundle.template?.status.title ?? "Not Created")
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.brandNavy)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(templateStatusColor)
            .clipShape(Capsule())
    }

    private var templateStatusColor: Color {
        switch model.bundle.template?.status {
        case .draft: .orange
        case .published: .green
        case .archived: .gray
        case .none: AppConstants.Colors.secondaryText
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink {
                OnboardingTemplateBuilderView(school: school, role: selectedRole)
            } label: {
                actionCard("Manage Template", icon: "square.and.pencil")
            }
            .buttonStyle(.plain)

            NavigationLink {
                OnboardingRecipientPreviewView(school: school, role: selectedRole, bundle: model.bundle)
            } label: {
                actionCard("Preview as \(selectedRole.title)", icon: "eye.fill")
            }
            .buttonStyle(.plain)
            .disabled(model.bundle.requirements.isEmpty)

            Button {
                showingInvite = true
            } label: {
                actionCard("Generate Invite Code", icon: "person.badge.key.fill")
            }
            .buttonStyle(.plain)
            .disabled(model.bundle.hasPublishedVersion == false)

            NavigationLink {
                AssignmentsView(filter: .documents)
            } label: {
                actionCard("Review Submissions", icon: "tray.full.fill", badge: model.progress.needsReviewCount)
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
                Label("How Templates Work", systemImage: "questionmark.circle.fill")
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
                        Label("How Templates Work", systemImage: "questionmark.circle")
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

    private let sampleStatuses = ["changes_requested", "in_review", "not_started", "approved"]

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewBanner
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Setup Checklist")
                            .font(.largeTitle.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text(school.name)
                            .font(.subheadline.bold())
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                        ProgressView(value: previewProgress)
                            .tint(.green)
                    }

                    ForEach(Array(bundle.requirements.enumerated()), id: \.element.id) { index, requirement in
                        let status = sampleStatuses[index % sampleStatuses.count]
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: onboardingStatusIcon(status))
                                    .foregroundColor(onboardingStatusColor(status))
                                Text(requirement.title)
                                    .font(.headline)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Spacer()
                                Text(onboardingStatusTitle(status))
                                    .font(.caption.bold())
                                    .foregroundColor(onboardingStatusColor(status))
                            }
                            if let description = requirement.description {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
                            }
                            if role.supportsChildSpecificOnboarding, requirement.subjectScope == .child {
                                Label("Example Child", systemImage: "figure.child")
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
                            }
                            Label("\(bundle.attachments(for: requirement.id).count) paperwork file(s)", systemImage: "paperclip")
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
                            Text(role.onboardingReviewerLabel)
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.48))
                            HStack {
                                Button("Download") {}
                                Button("Upload Completed Work") {}
                            }
                            .buttonStyle(.bordered)
                            .disabled(true)
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

    private var previewProgress: Double {
        guard bundle.requirements.isEmpty == false else { return 0 }
        return 1.0 / Double(bundle.requirements.count)
    }
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

    private var nextActionItem: OnboardingDashboardItem? {
        model.items.first { ["not_started", "in_progress", "changes_requested", "overdue"].contains($0.status) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if model.isLoading == false, let nextActionItem {
                            nextActionCard(nextActionItem)
                        }
                        if model.isLoading {
                            ProgressView("Loading setup")
                                .tint(AppConstants.Colors.accessibleYellow)
                                .foregroundColor(AppConstants.Colors.primaryText)
                        } else if model.items.isEmpty {
                            preparationCard
                        } else {
                            itemSection("Needs You", statuses: ["not_started", "in_progress", "changes_requested", "overdue"])
                            itemSection("Waiting on Review", statuses: ["in_review"])
                            itemSection("Complete", statuses: ["approved", "waived"])
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
            Text("\(completedCount) of \(model.items.count) approved")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
            ProgressView(value: model.items.isEmpty ? 0 : Double(completedCount) / Double(model.items.count))
                .tint(.green)
        }
    }

    private func nextActionCard(_ item: OnboardingDashboardItem) -> some View {
        Group {
            if let assignmentId = item.assignmentId {
                NavigationLink {
                    AssignmentDetailView(assignmentId: assignmentId) {
                        Task { await load() }
                    }
                } label: {
                    nextActionLabel(item)
                }
            } else {
                NavigationLink {
                    childConnectionDestination
                } label: {
                    nextActionLabel(item)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func nextActionLabel(_ item: OnboardingDashboardItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundColor(AppConstants.Colors.brandNavy)
            VStack(alignment: .leading, spacing: 3) {
                Text("Next action")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy.opacity(0.65))
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.brandNavy)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(AppConstants.Colors.brandNavy.opacity(0.55))
        }
        .padding()
        .background(AppConstants.Colors.accessibleYellow)
        .cornerRadius(10)
    }

    private var preparationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your setup is being prepared", systemImage: "clock.fill")
                .font(.headline)
                .foregroundColor(.orange)
            Text("Your school has not assigned the first requirement yet. Pull to refresh or contact the person who sent your invitation.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    @ViewBuilder
    private func itemSection(_ title: String, statuses: Set<String>) -> some View {
        let matches = model.items.filter { statuses.contains($0.status) }
        if matches.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                ForEach(matches) { item in
                    if let assignmentId = item.assignmentId {
                        NavigationLink {
                            AssignmentDetailView(assignmentId: assignmentId) {
                                Task { await load() }
                            }
                        } label: {
                            onboardingItemCard(item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            childConnectionDestination
                        } label: {
                            onboardingItemCard(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func onboardingItemCard(_ item: OnboardingDashboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: onboardingStatusIcon(item.status))
                    .foregroundColor(onboardingStatusColor(item.status))
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text(onboardingStatusTitle(item.status))
                    .font(.caption.bold())
                    .foregroundColor(onboardingStatusColor(item.status))
            }
            if let childName = item.childName {
                Label(childName, systemImage: "figure.child")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
            }
            if item.assignmentId == nil, item.subjectScope == .child {
                Text("Add or connect a child to create this requirement.")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            } else if let description = item.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                    .lineLimit(2)
            }
            Text(item.reviewerLabel)
                .font(.caption)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
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
                    helpSection("How to complete a requirement", "Open it, download any paperwork, attach the completed file or a supporting message, then submit it for review.", icon: "checklist")
                    helpSection("Waiting on review", "Your submission is with the authorized reviewer. You do not need to submit it again unless changes are requested.", icon: "clock.fill")
                    helpSection("Changes requested", "Read the reviewer message, make the correction, and submit a revised attempt from the same requirement.", icon: "arrow.uturn.backward.circle")
                    helpSection("Private paperwork", "Files use private storage and short-lived links. Only you, authorized guardians for child work, and the assigned reviewer can open them.", icon: "lock.shield.fill")
                    helpSection("File help", "FireflyFM accepts files up to \(UploadPolicy.maxFileSizeDescription). If an upload fails, confirm the file is available on this device and try again.", icon: "doc.badge.ellipsis")
                }
            }
            .navigationTitle(audience == .manager ? "How Templates Work" : "Setup Help")
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
