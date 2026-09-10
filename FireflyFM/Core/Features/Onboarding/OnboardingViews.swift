import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct OnboardingManagementView: View {
    let school: School
    let mode: OnboardingManagementMode

    @State private var selectedRole: SchoolRole
    @State private var model = OnboardingManagementModel()
    @State private var googleFormsCredential: GoogleFormsOAuthCompletion?
    @State private var didLoadGoogleFormsCredential = false
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
                Label(formSummaryLabel, systemImage: mode.usesHQInvitationFlow ? "building.2.crop.circle" : "list.clipboard.fill")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                statusBadge
            }
            Text(formSummaryTitle)
                .font(.title3.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(formSummaryDescription)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private var statusBadge: some View {
        Text(formConnectionStatus)
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.brandNavy)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(templateStatusColor)
            .clipShape(Capsule())
    }

    private var formConnectionStatus: String {
        if mode.usesHQInvitationFlow { return "HQ review" }
        if model.formsByRole[selectedRole]?.isEmpty == false { return "Forms connected" }
        if googleFormsCredential != nil { return "Forms connected" }
        return "Connect Google to add forms"
    }

    private var templateStatusColor: Color {
        mode.usesHQInvitationFlow
            || googleFormsCredential != nil
            || model.formsByRole[selectedRole]?.isEmpty == false
            ? .green
            : .orange
    }

    private var formSummaryLabel: String {
        mode.usesHQInvitationFlow ? "School director enrollment" : (selectedRole == .parent ? "Parent onboarding timeline" : "Teacher Google Forms")
    }

    private var formSummaryTitle: String {
        mode.usesHQInvitationFlow ? "HQ-managed director onboarding" : (selectedRole == .parent ? "One parent onboarding plan" : "Teacher onboarding forms")
    }

    private var formSummaryDescription: String {
        if mode.usesHQInvitationFlow {
            return "HQ manages director setup steps and reviews director contract or deposit payments. Google Forms are optional for this role."
        }
        return selectedRole == .parent
            ? "Put Forms and an optional Zelle payment in one clear order. Future parents see only the next step."
            : "Combine teacher Forms, paperwork, and an optional onboarding payment. FireflyFM keeps review feedback and access in one flow."
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if mode.usesHQInvitationFlow {
                NavigationLink {
                    PaymentsView()
                } label: {
                    actionCard("Set Zelle Instructions", icon: "dollarsign.circle.fill")
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    if selectedRole == .parent {
                        ParentOnboardingTimelineView(school: school)
                    } else {
                        GoogleFormOnboardingView(
                            school: school,
                            role: selectedRole,
                            sharedCredential: $googleFormsCredential
                        )
                    }
                } label: {
                    actionCard(selectedRole == .parent ? "Plan Parent Onboarding" : "Manage Teacher Forms", icon: "list.clipboard.fill")
                }
                .buttonStyle(.plain)
            }

            if mode.usesHQInvitationFlow == false && selectedRole == .teacher {
                NavigationLink {
                    OnboardingTemplateBuilderView(school: school, role: .teacher)
                } label: {
                    actionCard("Payments & Requirements", icon: "dollarsign.circle.fill")
                }
                .buttonStyle(.plain)
            }

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
            .disabled(canGenerateInvite == false)

            if !mode.usesHQInvitationFlow {
                NavigationLink {
                    GoogleFormReviewView(school: school)
                } label: {
                    actionCard("Review Form Responses", icon: "tray.full.fill", badge: model.progress.needsReviewCount)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var canGenerateInvite: Bool {
        if mode.usesHQInvitationFlow { return true }
        if selectedRole == .parent {
            return model.formsByRole[.parent]?.isEmpty == false
                && model.bundle.hasPublishedVersion
        }
        return model.bundle.hasPublishedVersion
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
        guard mode.usesHQInvitationFlow == false,
              didLoadGoogleFormsCredential == false else { return }
        do {
            googleFormsCredential = try await SchoolWorkflowService.shared
                .fetchGoogleFormsOAuthCredentials(schoolId: school.id)
                .first
            didLoadGoogleFormsCredential = true
        } catch where AppErrorMessage.isCancellation(error) {} catch {
            // Form setup loads the same connection and presents an actionable
            // error, so a dashboard refresh can retry this lightweight lookup.
        }
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
                Text("Version \(version) · Published edits update people still onboarding and future invitees.")
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
                        if requirement.requirementType == .payment,
                           let amount = requirement.paymentAmountCents {
                            Label(BillingMoney.string(cents: amount), systemImage: "dollarsign.circle")
                        } else {
                            Text(requirement.requirementType.rawValue.capitalized)
                        }
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
    @State private var requirementType: OnboardingRequirementType
    @State private var paymentAmount: String
    @State private var paymentDueDays: Int
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
        _requirementType = State(initialValue: requirement?.requirementType ?? .document)
        _paymentAmount = State(initialValue: requirement.flatMap(\.paymentAmountCents).map { BillingMoney.string(cents: $0) } ?? "")
        _paymentDueDays = State(initialValue: requirement?.paymentDueDays ?? 7)
        _retainedAttachments = State(initialValue: attachments)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Requirement") {
                    TextField("Title (for example, Signed enrollment agreement)", text: $title)
                    TextField("Description or instructions (optional)", text: $instructions, axis: .vertical)
                        .lineLimit(4...8)
                    Picker("Step type", selection: $requirementType) {
                        Text("Document").tag(OnboardingRequirementType.document)
                        Text("Acknowledgement").tag(OnboardingRequirementType.acknowledgement)
                        Text("Payment").tag(OnboardingRequirementType.payment)
                    }
                }

                if requirementType == .payment {
                    Section("Required payment") {
                        TextField("Amount", text: $paymentAmount)
                            .keyboardType(.decimalPad)
                        Stepper("Due within \(paymentDueDays) day\(paymentDueDays == 1 ? "" : "s")", value: $paymentDueDays, in: 1...90)
                        Text(paymentHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if role.supportsChildSpecificOnboarding {
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

                if requirementType != .payment {
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
            .onChange(of: requirementType) { _, newValue in
                if newValue == .payment {
                    subjectScope = .member
                    blocksAccess = true
                    childRecordBinding = .none
                    selectedFileURLs = []
                    retainedAttachments = []
                }
            }
        }
    }

    private var paymentHelpText: String {
        switch role {
        case .parent:
            "A payment step applies once to the invited parent, blocks access until the school director verifies it, and cannot include paperwork. Invite only the parent responsible for this fee."
        case .teacher:
            "A payment step applies once to the invited teacher, blocks access until the school director verifies it, and cannot include paperwork."
        case .schoolDirector:
            "A payment step applies once to the invited school director, blocks access until FireflyFM HQ verifies it, and cannot include paperwork."
        case .hqDirector:
            "A payment step applies once to the invited person and blocks access until the authorised reviewer verifies it."
        }
    }

    private func save() {
        Task {
            let amountCents = requirementType == .payment ? PaymentAmountParser.cents(from: paymentAmount) : nil
            guard requirementType != .payment || (amountCents ?? 0) >= 50 else {
                fileSelectionError = "Enter a payment amount of at least $0.50."
                return
            }
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
                    subjectScope: requirementType == .payment ? .member : (role.supportsChildSpecificOnboarding ? subjectScope : .member),
                    position: position,
                    attachments: requirementType == .payment ? [] : retained,
                    blocksAccess: requirementType == .payment ? true : (position == 0 ? true : blocksAccess),
                    childRecordBinding: requirementType == .payment ? .none : (subjectScope == .child ? childRecordBinding : .none),
                    requirementType: requirementType,
                    paymentAmountCents: amountCents.map(Int64.init),
                    paymentDueDays: requirementType == .payment ? paymentDueDays : nil
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

    private var cards: [(String, String, String, String)] {
        let standard: [(String, String, String, String)] = [
            ("Invitation", "Your school invitation is connected to this account.", "Complete", "envelope.badge.fill"),
            (role == .parent ? "Parent intake form" : "Teacher onboarding form",
             role == .parent ? "Share child and required document information." : "Complete your required staff information.",
             "Ready", "list.clipboard.fill"),
            ("School review", "FireflyFM imports the response, updates approved records, and refreshes access after review.",
             "Waiting", "checkmark.seal.fill")
        ]
        let paymentSteps = bundle.requirements.compactMap { requirement -> (String, String, String, String)? in
            guard requirement.requirementType == .payment,
                  let amount = requirement.paymentAmountCents else { return nil }
            return (
                requirement.title,
                "Send \(BillingMoney.string(cents: amount)) through your bank’s Zelle experience, then submit a short confirmation reference for authorised review.",
                "Required",
                "dollarsign.circle.fill"
            )
        }
        return standard + paymentSteps
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewBanner
                    VStack(alignment: .leading, spacing: 6) {
                        Text(role == .parent ? "Parent onboarding" : "Teacher onboarding")
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
    let connectionID: UUID?
    let icon: String
    let title: String
    let description: String
    let status: String
}

private struct OnboardingPaymentRoute: Identifiable {
    let id: UUID
}

struct OnboardingAccessGateView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager

    @State private var model = OnboardingAccessGateModel()
    @State private var showingHelp = false
    @State private var showingSignOutConfirmation = false
    @State private var googleFormSteps: [GoogleFormRecipientStep] = []
    @State private var parentTimeline: [ParentOnboardingTimelineItem] = []
    @State private var formURLToOpen: URL?
    @State private var showingForm = false
    @State private var paymentRoute: OnboardingPaymentRoute?

    private var completedCount: Int {
        model.items.filter { ["approved", "waived"].contains($0.status) }.count
    }

    private var hasAttentionNeeded: Bool {
        model.items.contains { ["changes_requested", "overdue"].contains($0.status) }
    }

    private var isApproved: Bool {
        !model.items.isEmpty && completedCount == model.items.count
    }

    private var usesParentTimeline: Bool {
        appSession.role == .parent
    }

    private var nextParentTimelineItem: ParentOnboardingTimelineItem? {
        parentTimeline.first(where: { !isTimelineComplete($0) })
    }

    private var recipientSteps: [RecipientFormStep] {
        guard googleFormSteps.isEmpty == false else { return [] }
        let next = googleFormSteps.first(where: { step in
            step.submissionStatus != "approved"
        }) ?? googleFormSteps.last!
        return [RecipientFormStep(
            id: "form-\(next.connectionId.uuidString)", connectionID: next.connectionId,
            icon: "doc.text.fill", title: next.formTitle ?? "Onboarding form",
            description: formDescription(for: next), status: formStatus(for: next)
        )]
    }

    private var paymentItems: [OnboardingDashboardItem] {
        usesParentTimeline ? [] : model.items.filter { $0.requirementType == .payment }
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
        .sheet(isPresented: $showingForm) {
            if let url = formURLToOpen {
                FireflySafariView(url: url).ignoresSafeArea()
            }
        }
        .sheet(item: $paymentRoute) { route in
            NavigationStack {
                ZelleInvoiceDestinationView(invoiceId: route.id, schoolId: appSession.activeSchool?.id ?? UUID())
            }
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
        if hasAttentionNeeded { return "\(onboardingReviewerSubject) requested an update" }
        if usesParentTimeline {
            guard let next = nextParentTimelineItem else {
                return parentTimeline.isEmpty ? "Waiting for \(onboardingReviewerName) to assign onboarding" : "Onboarding complete"
            }
            if next.isForm {
                switch next.formSubmissionStatus {
                case "changes_requested", "rejected": return "\(onboardingReviewerSubject) requested an update"
                case "pending_review": return "Information submitted — awaiting \(onboardingReviewerName) review"
                default: return "Complete the next required Form"
                }
            }
            switch next.zelleInvoiceStatus {
            case .paymentSubmitted, .underReview: return "Payment submitted — awaiting \(onboardingReviewerName) review"
            case .rejected: return "\(onboardingReviewerSubject) requested a payment update"
            default: return "Complete the next required payment"
            }
        }
        if isApproved { return "Onboarding complete" }
        if paymentItems.contains(where: { $0.zelleInvoiceStatus == .rejected }) { return "\(onboardingReviewerSubject) requested a payment update" }
        if paymentItems.contains(where: { item in
            guard let status = item.zelleInvoiceStatus else { return false }
            return [.paymentSubmitted, .underReview].contains(status)
        }) { return "Payment submitted — awaiting \(onboardingReviewerName) review" }
        if paymentItems.contains(where: { $0.zelleInvoiceStatus == .open }) { return "Complete the next required payment" }
        if googleFormSteps.isEmpty { return "Waiting for \(onboardingReviewerName) to assign a Form" }
        if googleFormSteps.contains(where: { $0.submissionStatus == "changes_requested" }) { return "\(onboardingReviewerSubject) requested an update" }
        if googleFormSteps.contains(where: { $0.submissionStatus == "pending_review" }) { return "Information submitted — awaiting \(onboardingReviewerName) review" }
        return "Complete the next required Form"
    }

    private var onboardingReviewerName: String {
        appSession.role == .schoolDirector ? "FireflyFM HQ" : "your school"
    }

    private var onboardingReviewerSubject: String {
        appSession.role == .schoolDirector ? "FireflyFM HQ" : "Your school"
    }

    @ViewBuilder
    private var formSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Onboarding steps")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            if usesParentTimeline {
                if let item = nextParentTimelineItem {
                    parentTimelineCard(item)
                } else if parentTimeline.isEmpty {
                    Text("Your school has not assigned an onboarding plan yet.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
                } else {
                    Label("Every onboarding step is complete.", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            } else {
                ForEach(recipientSteps) { step in
                    if let connectionID = step.connectionID, isFormActionable(connectionID) {
                        Button { Task { await launchForm(connectionID) } } label: {
                            formStepCard(step, isActionable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        formStepCard(step, isActionable: false)
                    }
                }
                ForEach(paymentItems) { item in
                    let step = RecipientFormStep(
                        id: "payment-\(item.requirementInstanceId.uuidString)",
                        connectionID: nil,
                        icon: "dollarsign.circle.fill",
                        title: item.title,
                        description: paymentDescription(for: item),
                        status: paymentStatus(for: item)
                    )
                    if let invoiceId = item.zelleInvoiceId, isPaymentActionable(item) {
                        Button { paymentRoute = OnboardingPaymentRoute(id: invoiceId) } label: {
                            formStepCard(step, isActionable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        formStepCard(step, isActionable: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func parentTimelineCard(_ item: ParentOnboardingTimelineItem) -> some View {
        let step = RecipientFormStep(
            id: "timeline-\(item.requirementInstanceId.uuidString)",
            connectionID: item.connectionId,
            icon: item.isForm ? "doc.text.fill" : "dollarsign.circle.fill",
            title: item.isForm ? (item.formTitle ?? item.title) : item.title,
            description: timelineDescription(for: item),
            status: timelineStatus(for: item)
        )
        if item.isForm, let connectionID = item.connectionId, isTimelineFormActionable(item) {
            Button { Task { await launchForm(connectionID) } } label: {
                formStepCard(step, isActionable: true)
            }
            .buttonStyle(.plain)
        } else if item.isPayment, let invoiceID = item.zelleInvoiceId, isTimelinePaymentActionable(item) {
            Button { paymentRoute = OnboardingPaymentRoute(id: invoiceID) } label: {
                formStepCard(step, isActionable: true)
            }
            .buttonStyle(.plain)
        } else {
            formStepCard(step, isActionable: false)
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

    private func formStatus(for step: GoogleFormRecipientStep) -> String {
        switch step.submissionStatus {
        case "approved": "Complete"
        case "pending_review": "Awaiting review"
        case "changes_requested": "Update requested"
        case "rejected": "Submit new response"
        case "ambiguous", "error": "School review needed"
        default: "Ready"
        }
    }

    private func formDescription(for step: GoogleFormRecipientStep) -> String {
        if let note = step.reviewNote, note.isEmpty == false { return note }
        switch step.submissionStatus {
        case "pending_review": return "Your information has been submitted and is awaiting school review."
        case "approved": return "This Form has been approved."
        case "changes_requested": return "Open the Form to submit an updated response."
        case "rejected": return "Open the Form to submit a new response for review."
        default: return step.formRole == "parent" ? "Share child and required document information." : "Complete your required staff information."
        }
    }

    private func isFormActionable(_ connectionID: UUID) -> Bool {
        guard let step = googleFormSteps.first(where: { $0.connectionId == connectionID }) else { return false }
        return !["approved", "pending_review"].contains(step.submissionStatus)
    }

    private func isTimelineComplete(_ item: ParentOnboardingTimelineItem) -> Bool {
        if ["approved", "waived"].contains(item.status) { return true }
        if item.isForm { return item.formSubmissionStatus == "approved" }
        return item.zelleInvoiceStatus == .paid || item.zelleInvoiceStatus == .void
    }

    private func timelineStatus(for item: ParentOnboardingTimelineItem) -> String {
        if item.isForm {
            switch item.formSubmissionStatus {
            case "approved": return "Complete"
            case "pending_review": return "Awaiting review"
            case "changes_requested": return "Update requested"
            case "rejected": return "Submit new response"
            case "ambiguous", "error": return "School review needed"
            default: return "Ready"
            }
        }
        switch item.zelleInvoiceStatus {
        case .paid: return "Complete"
        case .paymentSubmitted, .underReview: return "Awaiting review"
        case .rejected: return "Update requested"
        case .void: return "Waived"
        case .expired: return "Contact school"
        case .open: return "Ready to pay"
        case .draft, .none: return "Preparing"
        }
    }

    private func timelineDescription(for item: ParentOnboardingTimelineItem) -> String {
        if item.isForm {
            if let note = item.formReviewNote, !note.isEmpty { return note }
            switch item.formSubmissionStatus {
            case "pending_review": return "Your information has been submitted and is awaiting school review."
            case "changes_requested": return "Open the Form to submit an updated response."
            case "rejected": return "Open the Form to submit a new response for review."
            default: return "Share the requested child and family information."
            }
        }
        if let amount = item.zelleAmountDueCents {
            let amountText = BillingMoney.string(cents: amount)
            switch item.zelleInvoiceStatus {
            case .paymentSubmitted, .underReview: return "\(amountText) submitted. Your school will verify the transfer."
            case .rejected: return "Submit an updated \(amountText) payment confirmation for review."
            case .paid: return "\(amountText) has been verified."
            default: return "Send \(amountText) through your bank’s Zelle experience, then submit the confirmation reference."
            }
        }
        return "\(onboardingReviewerSubject) is preparing this payment step."
    }

    private func isTimelineFormActionable(_ item: ParentOnboardingTimelineItem) -> Bool {
        !["approved", "pending_review", "ambiguous", "error"].contains(item.formSubmissionStatus)
    }

    private func isTimelinePaymentActionable(_ item: ParentOnboardingTimelineItem) -> Bool {
        guard let status = item.zelleInvoiceStatus else { return false }
        return [.open, .rejected].contains(status)
    }

    private func paymentStatus(for item: OnboardingDashboardItem) -> String {
        switch item.zelleInvoiceStatus {
        case .paid: "Complete"
        case .paymentSubmitted, .underReview: "Awaiting review"
        case .rejected: "Update requested"
        case .void: "Waived"
        case .expired: "Contact school"
        case .open: "Ready to pay"
        case .draft, .none: "Preparing"
        }
    }

    private func paymentDescription(for item: OnboardingDashboardItem) -> String {
        if let amount = item.zelleAmountDueCents {
            let amountText = BillingMoney.string(cents: amount)
            switch item.zelleInvoiceStatus {
            case .paymentSubmitted, .underReview:
                return "\(amountText) submitted. \(item.reviewerLabel) will verify the transfer."
            case .rejected:
                return "Submit an updated \(amountText) payment confirmation for review."
            case .paid:
                return "\(amountText) has been verified."
            default:
                return "Send \(amountText) through your bank’s Zelle experience, then submit the confirmation reference."
            }
        }
        return "\(onboardingReviewerSubject) is preparing this payment step."
    }

    private func isPaymentActionable(_ item: OnboardingDashboardItem) -> Bool {
        guard let status = item.zelleInvoiceStatus else { return false }
        return [.open, .rejected].contains(status)
    }

    @MainActor
    private func launchForm(_ connectionID: UUID) async {
        do {
            let launch = try await SchoolWorkflowService.shared.beginGoogleFormSubmission(connectionId: connectionID)
            guard let url = URL(string: launch.launchURL) else { throw SchoolWorkflowError.invalidInput("The Form launch link was invalid.") }
            formURLToOpen = url
            showingForm = true
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            model.setError(AppErrorMessage.school("Could not open the Form", error))
        }
    }

    @MainActor
    private func load() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        if await model.load(schoolId: schoolId) { await appSession.refresh() }
        guard !Task.isCancelled else { return }
        do {
            if usesParentTimeline {
                parentTimeline = try await SchoolWorkflowService.shared.fetchMyParentOnboardingTimeline(schoolId: schoolId)
                googleFormSteps = []
            } else {
                googleFormSteps = try await SchoolWorkflowService.shared.fetchMyGoogleFormSteps(schoolId: schoolId)
                parentTimeline = []
            }
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            model.setError(AppErrorMessage.school("Could not load your next onboarding step", error))
        }
    }
}

private struct GoogleFormResponseConfirmationView: View {
    let item: GoogleFormImport
    let formURL: String?
    @State private var showingForm = false

    var body: some View {
        Form {
            Section("Submission") {
                LabeledContent("Status", value: item.status.replacingOccurrences(of: "_", with: " ").capitalized)
                LabeledContent("Submitted", value: item.responseSubmittedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Date unavailable")
            }
            Section("Your answers") {
                ForEach(item.submittedPayload.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: item.submittedPayload[key]?.confirmationValue ?? "Not provided")
                }
            }
            Section("Documents") {
                Text("Uploaded documents are attached to your submission and will appear in the child Documents view after review.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let note = item.reviewNote, note.isEmpty == false {
                Section("School feedback") {
                    Text(note)
                }
            }
        }
        .navigationTitle("Submitted Response")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if formURL != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit an update") { showingForm = true }
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            if let formURL, let url = URL(string: formURL) {
                FireflySafariView(url: url).ignoresSafeArea()
            }
        }
    }
}

private extension FireflyJSONValue {
    var confirmationValue: String? {
        switch self {
        case let .string(value): value
        case let .number(value): String(value)
        case let .bool(value): value ? "Yes" : "No"
        case let .array(values): values.compactMap(\.confirmationValue).joined(separator: ", ")
        case .object: "Structured answer"
        case .null: nil
        }
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
    @State private var isPaymentPayer = true
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
                if role == .parent {
                    Section("Onboarding payment") {
                        Toggle("This parent handles the onboarding payment", isOn: $isPaymentPayer)
                        Text("All invited parents complete the Forms. Choose one parent for a required payment so a family is not charged twice.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    role: role,
                    isPaymentPayer: role == .parent ? isPaymentPayer : nil
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
                    helpSection("Requirements are automatic", "Every published item is assigned to people currently onboarding and future \(role.title.lowercased()) invitees, and blocks full access until approved or waived.", icon: "wand.and.stars")
                    helpSection("Review is already assigned", role.onboardingManagerReviewHelp, icon: "person.badge.shield.checkmark")
                    helpSection("Published changes stay current", "Editing creates a draft. When it is published, unfinished onboarding updates to that version while approved, waived, and completed payment work is preserved.", icon: "clock.arrow.circlepath")
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
