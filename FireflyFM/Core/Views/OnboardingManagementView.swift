import SwiftUI
import UniformTypeIdentifiers

enum OnboardingManagementMode: Hashable {
    case hqDirector
    case schoolDirector
}

struct OnboardingManagementView: View {
    let school: School
    let mode: OnboardingManagementMode

    @State private var selectedRole: SchoolRole
    @State private var bundle = OnboardingTemplateBundle(template: nil, requirements: [], attachments: [])
    @State private var progress = OnboardingRoleProgress.empty
    @State private var isLoading = true
    @State private var showingInvite = false
    @State private var showingHelp = false
    @State private var errorMessage: String?

    init(school: School, mode: OnboardingManagementMode) {
        self.school = school
        self.mode = mode
        _selectedRole = State(initialValue: mode == .hqDirector ? .schoolDirector : .parent)
    }

    private var availableRoles: [SchoolRole] {
        mode == .hqDirector ? [.schoolDirector] : [.parent, .teacher]
    }

    private var roleTitle: String {
        switch selectedRole {
        case .schoolDirector: "School Director Onboarding"
        case .parent: "Parent Onboarding"
        case .teacher: "Teacher Onboarding"
        case .hqDirector: "Onboarding"
        }
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
                    if let errorMessage {
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
            if mode == .hqDirector {
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
            Text(bundle.template?.name ?? roleTitle)
                .font(.title3.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(bundle.requirements.isEmpty
                 ? "No requirements yet. Add the first requirement to begin."
                 : "\(bundle.requirements.count) requirement\(bundle.requirements.count == 1 ? "" : "s") · All requirements block full access.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
            if bundle.template?.status == .draft, bundle.template?.version ?? 1 > 1 {
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
        Text(bundle.template?.status.title ?? "Not Created")
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.brandNavy)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(templateStatusColor)
            .clipShape(Capsule())
    }

    private var templateStatusColor: Color {
        switch bundle.template?.status {
        case .draft: .orange
        case .published: .green
        case .archived: .gray
        case .none: .white.opacity(0.65)
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
                OnboardingRecipientPreviewView(school: school, role: selectedRole, bundle: bundle)
            } label: {
                actionCard("Preview as \(selectedRole.title)", icon: "eye.fill")
            }
            .buttonStyle(.plain)
            .disabled(bundle.requirements.isEmpty)

            Button {
                showingInvite = true
            } label: {
                actionCard(selectedRole == .schoolDirector ? "Invite Director" : "Invite People", icon: "person.badge.plus")
            }
            .buttonStyle(.plain)
            .disabled(bundle.hasPublishedVersion == false)

            NavigationLink {
                AssignmentsView(surface: .documents)
            } label: {
                actionCard("Review Submissions", icon: "tray.full.fill", badge: progress.needsReviewCount)
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
                metric("Invited", value: progress.memberCount, color: .white)
                metric("In Setup", value: progress.onboardingCount, color: .orange)
                metric("Full Access", value: progress.fullCount, color: .green)
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
        isLoading = true
        errorMessage = nil
        do {
            async let loadedBundle = SchoolWorkflowService.shared.fetchOnboardingTemplate(schoolId: school.id, role: selectedRole)
            async let loadedProgress = SchoolWorkflowService.shared.fetchOnboardingRoleProgress(schoolId: school.id, role: selectedRole)
            (bundle, progress) = try await (loadedBundle, loadedProgress)
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load onboarding", error)
            isLoading = false
        }
    }
}

struct OnboardingTemplateBuilderView: View {
    let school: School
    let role: SchoolRole

    @State private var bundle = OnboardingTemplateBundle(template: nil, requirements: [], attachments: [])
    @State private var editorContext: RequirementEditorContext?
    @State private var lastDeleted: DeletedRequirementSnapshot?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showingHelp = false
    @State private var showingArchiveConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            List {
                Section {
                    templateHeader
                }
                .listRowBackground(AppConstants.Colors.card)

                Section("Requirements") {
                    if isLoading {
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    } else if bundle.requirements.isEmpty {
                        emptyTemplate
                    } else {
                        ForEach(bundle.requirements) { requirement in
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
                    .disabled(isSaving)

                    if let template = bundle.template, template.status == .draft {
                        Button {
                            publish(template)
                        } label: {
                            Label("Publish Changes", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(bundle.requirements.isEmpty || isSaving)
                    }

                    NavigationLink {
                        OnboardingRecipientPreviewView(school: school, role: role, bundle: bundle)
                    } label: {
                        Label("Preview as Recipient", systemImage: "eye.fill")
                    }
                    .disabled(bundle.requirements.isEmpty)
                }
                .listRowBackground(AppConstants.Colors.card)

                if let errorMessage {
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
                if bundle.template?.status == .draft, bundle.requirements.count > 1 {
                    EditButton()
                }
                Menu {
                    Button { showingHelp = true } label: {
                        Label("How Templates Work", systemImage: "questionmark.circle")
                    }
                    if bundle.template != nil {
                        Button(role: .destructive) { showingArchiveConfirmation = true } label: {
                            Label(
                                bundle.template?.status == .draft ? "Delete Draft" : "Archive Template",
                                systemImage: bundle.template?.status == .draft ? "trash" : "archivebox"
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
            if let template = bundle.template {
                OnboardingRequirementEditorView(
                    school: school,
                    role: role,
                    template: template,
                    requirement: context.requirement,
                    attachments: context.requirement.map { bundle.attachments(for: $0.id) } ?? [],
                    position: context.requirement?.position ?? bundle.requirements.count
                ) {
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            OnboardingHelpView(audience: .manager, role: role)
        }
        .confirmationDialog(
            bundle.template?.status == .draft ? "Delete this unused draft?" : "Archive this template?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                bundle.template?.status == .draft ? "Delete Draft" : "Archive Template",
                role: .destructive
            ) { removeTemplate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bundle.template?.status == .draft
                 ? "This draft has never been assigned. Its requirements will be permanently removed; the last published version stays available."
                 : "Existing onboarding stays intact. New invitations are paused until another version is published.")
        }
        .safeAreaInset(edge: .bottom) {
            if lastDeleted != nil {
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
        switch role {
        case .schoolDirector: "Director Template"
        case .parent: "Parent Template"
        case .teacher: "Teacher Template"
        case .hqDirector: "Template"
        }
    }

    private var templateHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(bundle.template?.name ?? roleTemplateTitle)
                    .font(.title2.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text(bundle.template?.status.title ?? "Not Created")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(bundle.template?.status == .published ? .green : .orange)
                    .clipShape(Capsule())
            }
            Text("Add a title, instructions, and any paperwork. FireflyFM handles assignment, review, feedback, and access automatically.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
            if let version = bundle.template?.version {
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
                        Label("\(bundle.attachments(for: requirement.id).count)", systemImage: "paperclip")
                        if role == .parent {
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
            isSaving = true
            do {
                let draft = try await SchoolWorkflowService.shared.ensureOnboardingTemplateDraft(schoolId: school.id, role: role)
                await load()
                let mapped = original.flatMap { original in
                    bundle.requirements.first { $0.id == original.id }
                    ?? bundle.requirements.first { $0.position == original.position && $0.title == original.title }
                }
                bundle.template = draft
                editorContext = RequirementEditorContext(requirement: mapped)
                isSaving = false
            } catch {
                errorMessage = AppErrorMessage.school("Could not prepare the template", error)
                isSaving = false
            }
        }
    }

    private func duplicate(_ original: OnboardingTemplateRequirement) {
        Task {
            isSaving = true
            do {
                _ = try await SchoolWorkflowService.shared.ensureOnboardingTemplateDraft(schoolId: school.id, role: role)
                await load()
                guard let template = bundle.template else { return }
                let source = bundle.requirements.first { $0.id == original.id }
                    ?? bundle.requirements.first { $0.position == original.position && $0.title == original.title }
                    ?? original
                let attachments = bundle.attachments(for: source.id).map {
                    OnboardingAttachmentDescriptor(privateFilePath: $0.privateFilePath, fileName: $0.fileName, contentType: $0.contentType)
                }
                _ = try await SchoolWorkflowService.shared.saveOnboardingTemplateRequirement(
                    templateId: template.id,
                    requirementId: nil,
                    title: "\(source.title) Copy",
                    description: source.description,
                    subjectScope: source.subjectScope,
                    position: bundle.requirements.count,
                    attachments: attachments
                )
                await load()
                isSaving = false
            } catch {
                errorMessage = AppErrorMessage.school("Could not duplicate requirement", error)
                isSaving = false
            }
        }
    }

    private func remove(_ original: OnboardingTemplateRequirement) {
        Task {
            isSaving = true
            do {
                _ = try await SchoolWorkflowService.shared.ensureOnboardingTemplateDraft(schoolId: school.id, role: role)
                await load()
                guard let mapped = bundle.requirements.first(where: { $0.id == original.id })
                        ?? bundle.requirements.first(where: { $0.position == original.position && $0.title == original.title }) else { return }
                lastDeleted = DeletedRequirementSnapshot(
                    requirement: mapped,
                    attachments: bundle.attachments(for: mapped.id).map {
                        OnboardingAttachmentDescriptor(privateFilePath: $0.privateFilePath, fileName: $0.fileName, contentType: $0.contentType)
                    }
                )
                try await SchoolWorkflowService.shared.removeOnboardingTemplateRequirement(requirementId: mapped.id)
                await load()
                isSaving = false
            } catch {
                errorMessage = AppErrorMessage.school("Could not remove requirement", error)
                isSaving = false
            }
        }
    }

    private func undoDelete() {
        guard let snapshot = lastDeleted, let template = bundle.template else { return }
        lastDeleted = nil
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.saveOnboardingTemplateRequirement(
                    templateId: template.id,
                    requirementId: nil,
                    title: snapshot.requirement.title,
                    description: snapshot.requirement.description,
                    subjectScope: snapshot.requirement.subjectScope,
                    position: bundle.requirements.count,
                    attachments: snapshot.attachments
                )
                await load()
            } catch {
                errorMessage = AppErrorMessage.school("Could not restore requirement", error)
            }
        }
    }

    private func moveRequirements(from source: IndexSet, to destination: Int) {
        guard let template = bundle.template, template.status == .draft else { return }
        var reordered = bundle.requirements
        reordered.move(fromOffsets: source, toOffset: destination)
        bundle.requirements = reordered.enumerated().map { index, value in
            var copy = value
            copy.position = index
            return copy
        }
        Task {
            do {
                try await SchoolWorkflowService.shared.reorderOnboardingTemplateRequirements(
                    templateId: template.id,
                    requirementIds: reordered.map(\.id)
                )
            } catch {
                errorMessage = AppErrorMessage.school("Could not reorder requirements", error)
                await load()
            }
        }
    }

    private func publish(_ template: OnboardingTemplate) {
        isSaving = true
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.publishOnboardingTemplate(templateId: template.id)
                await load()
                isSaving = false
            } catch {
                errorMessage = AppErrorMessage.school("Could not publish template", error)
                isSaving = false
            }
        }
    }

    private func removeTemplate() {
        guard let template = bundle.template else { return }
        Task {
            do {
                if template.status == .draft {
                    try await SchoolWorkflowService.shared.deleteOnboardingTemplateDraft(templateId: template.id)
                } else {
                    _ = try await SchoolWorkflowService.shared.archiveOnboardingTemplate(templateId: template.id)
                }
                await load()
            } catch {
                errorMessage = AppErrorMessage.school("Could not remove template", error)
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            bundle = try await SchoolWorkflowService.shared.fetchOnboardingTemplate(schoolId: school.id, role: role)
            errorMessage = nil
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not load template", error)
        }
        isLoading = false
    }
}

private struct RequirementEditorContext: Identifiable {
    let id = UUID()
    let requirement: OnboardingTemplateRequirement?
}

private struct DeletedRequirementSnapshot {
    let requirement: OnboardingTemplateRequirement
    let attachments: [OnboardingAttachmentDescriptor]
}

private struct OnboardingRequirementEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    let role: SchoolRole
    let template: OnboardingTemplate
    let requirement: OnboardingTemplateRequirement?
    let position: Int
    var onSaved: () -> Void

    @State private var title: String
    @State private var instructions: String
    @State private var subjectScope: OnboardingSubjectScope
    @State private var retainedAttachments: [OnboardingTemplateAttachment]
    @State private var selectedFileURLs: [URL] = []
    @State private var editorId = UUID()
    @State private var showingImporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?

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

                if role == .parent {
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

                if let errorMessage {
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
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                do {
                    let urls = try result.get()
                    selectedFileURLs.append(contentsOf: urls.filter { selectedFileURLs.contains($0) == false })
                } catch {
                    errorMessage = "The selected paperwork could not be opened."
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            var newlyUploaded: [OnboardingAttachmentDescriptor] = []
            do {
                var descriptors = retainedAttachments.map {
                    OnboardingAttachmentDescriptor(privateFilePath: $0.privateFilePath, fileName: $0.fileName, contentType: $0.contentType)
                }
                for fileURL in selectedFileURLs {
                    let uploaded = try await SchoolWorkflowService.shared.uploadOnboardingTemplateAttachment(
                        schoolId: school.id,
                        templateId: template.id,
                        editorId: editorId,
                        fileURL: fileURL
                    )
                    newlyUploaded.append(uploaded)
                    descriptors.append(uploaded)
                }
                _ = try await SchoolWorkflowService.shared.saveOnboardingTemplateRequirement(
                    templateId: template.id,
                    requirementId: requirement?.id,
                    title: title,
                    description: instructions,
                    subjectScope: role == .parent ? subjectScope : .member,
                    position: position,
                    attachments: descriptors
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                try? await SchoolService.shared.removePrivateFiles(paths: newlyUploaded.map(\.privateFilePath))
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not save requirement", error)
                    isSaving = false
                }
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
                            if role == .parent, requirement.subjectScope == .child {
                                Label("Example Child", systemImage: "figure.child")
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
                            }
                            Label("\(bundle.attachments(for: requirement.id).count) paperwork file(s)", systemImage: "paperclip")
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
                            Text(role == .schoolDirector ? "Reviewed by FireflyFM HQ" : "Reviewed by your school director")
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

    @State private var items: [OnboardingDashboardItem] = []
    @State private var isLoading = true
    @State private var showingHelp = false
    @State private var showingSignOutConfirmation = false
    @State private var errorMessage: String?

    private var completedCount: Int {
        items.filter { ["approved", "waived"].contains($0.status) }.count
    }

    private var nextActionItem: OnboardingDashboardItem? {
        items.first { ["not_started", "in_progress", "changes_requested", "overdue"].contains($0.status) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if isLoading == false, let nextActionItem {
                            nextActionCard(nextActionItem)
                        }
                        if isLoading {
                            ProgressView("Loading setup")
                                .tint(AppConstants.Colors.accessibleYellow)
                                .foregroundColor(AppConstants.Colors.primaryText)
                        } else if items.isEmpty {
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
                        if let errorMessage {
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
            Text("\(completedCount) of \(items.count) approved")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
            ProgressView(value: items.isEmpty ? 0 : Double(completedCount) / Double(items.count))
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
                    ChildrenView()
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
        let matches = items.filter { statuses.contains($0.status) }
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
                            ChildrenView()
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

    @MainActor
    private func load() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        do {
            items = try await SchoolWorkflowService.shared.fetchMyOnboardingDashboard(schoolId: schoolId)
            errorMessage = nil
            if items.isEmpty == false && completedCount == items.count {
                await appSession.refresh()
            }
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not load setup", error)
        }
        isLoading = false
    }
}

private struct OnboardingMemberInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    let role: SchoolRole
    var onInvited: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var createdInvite: RoleInvite?
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                    Text("The link works only for this email address and expires after 14 days. Accepting it assigns the published \(role.title.lowercased()) template automatically.")
                        .font(.caption)
                }
                if let inviteURL = createdInvite?.inviteURL {
                    Section("Invitation Ready") {
                        ShareLink(item: inviteURL) {
                            Label("Share Sign-In Link", systemImage: "square.and.arrow.up")
                        }
                        Text(inviteURL.absoluteString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        if let fallback = createdInvite?.manualInviteURL, fallback != inviteURL {
                            ShareLink(item: fallback) {
                                Label("Share Manual App Link", systemImage: "link")
                            }
                            Text("Use the manual link if the HTTPS link does not open the app.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Invite \(role.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdInvite == nil ? "Cancel" : "Done") { dismiss() }
                }
                if createdInvite == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Creating" : "Create Link") { createInvite() }
                            .disabled(email.contains("@") == false || isSaving)
                    }
                }
            }
        }
    }

    private func createInvite() {
        isSaving = true
        Task {
            do {
                createdInvite = try await SchoolService.shared.createMemberRoleInvite(
                    schoolId: school.id,
                    email: email,
                    displayName: name,
                    role: role
                )
                isSaving = false
                onInvited()
            } catch {
                errorMessage = AppErrorMessage.school("Could not create invitation", error)
                isSaving = false
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
                    helpSection("Review is already assigned", role == .schoolDirector ? "FireflyFM HQ reviews director work." : "The approved school director reviews parent and teacher work.", icon: "person.badge.shield.checkmark")
                    helpSection("Published changes are safe", "Editing creates a draft for future invitees. People already in setup keep the version they received.", icon: "clock.arrow.circlepath")
                    helpSection("Delete drafts; archive published work", "An unused draft can be deleted. Once published, the template remains in the audit history and can only be archived, which pauses new invitations without changing existing work.", icon: "archivebox")
                    if role == .parent {
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
    case "not_started": .white.opacity(0.48)
    case "in_progress": AppConstants.Colors.accessibleYellow
    case "in_review": .orange
    case "changes_requested", "overdue": .red
    case "approved": .green
    case "waived": .cyan
    default: .white.opacity(0.48)
    }
}
