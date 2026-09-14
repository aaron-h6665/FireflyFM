//
//  AssignmentComposerView.swift
//  FireflyFM
//

import SwiftUI
import UniformTypeIdentifiers

struct AssignmentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let filter: AssignmentFilter
    let schoolId: UUID
    let schools: [School]
    let defaultCategory: AssignmentCategory
    var onSaved: () -> Void

    private let materialDraftStore = AssignmentDraftAttachmentStore()

    @State private var model = AssignmentComposerModel()
    @State private var title = ""
    @State private var description = ""
    @State private var category: AssignmentCategory
    @State private var schoolTarget: AssignmentSchoolTarget = .one
    @State private var selectedSchoolId: UUID
    @State private var selectedSchoolIds: Set<UUID>
    @State private var step: AssignmentComposerStep = .what
    @State private var audienceMode: AssignmentAudienceMode = .people
    @State private var selectedAudienceRole: SchoolRole = .teacher
    @State private var publication: AssignmentPublicationChoice = .published
    @State private var publishAt = Date().addingTimeInterval(24 * 60 * 60)
    @State private var dueAt = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @State private var hasDueDate = true
    @State private var materialType = "file"
    @State private var materialURL = ""
    @State private var materialURLs: [String] = []
    @State private var webURL: URL?
    @State private var selectedMaterialFileURLs: [URL] = []
    @State private var showingMaterialImporter = false
    @State private var materialDraftId = UUID()
    @State private var selectedRecipientKeys = Set<AssignmentRecipientSelectionKey>()
    @State private var selectedChildId: UUID?
    @State private var searchText = ""
    @State private var mutationKey = UUID().uuidString
    @State private var validationError: String?

    init(
        filter: AssignmentFilter,
        schoolId: UUID,
        schools: [School] = [],
        defaultCategory: AssignmentCategory,
        onSaved: @escaping () -> Void
    ) {
        self.filter = filter
        self.schoolId = schoolId
        self.schools = schools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.defaultCategory = defaultCategory
        self.onSaved = onSaved
        _category = State(initialValue: defaultCategory)
        _selectedSchoolId = State(initialValue: schoolId)
        _selectedSchoolIds = State(initialValue: [schoolId])
    }

    private var availableCategories: [AssignmentCategory] {
        (filter.categories ?? [.training, .curriculum])
            .filter { $0 == .training || $0 == .curriculum }
    }

    private var supportsMultipleSchools: Bool { schools.count > 1 }
    private var destinationSchoolIds: [UUID] {
        switch schoolTarget {
        case .one:
            [selectedSchoolId]
        case .selected:
            schools.filter { selectedSchoolIds.contains($0.id) }.map(\.id)
        case .all:
            schools.map(\.id)
        }
    }
    private var isMultiSchoolAudience: Bool { destinationSchoolIds.count > 1 }
    private var members: [SchoolMember] {
        destinationSchoolIds.flatMap { model.membersBySchool[$0] ?? [] }
    }
    private var children: [Child] {
        guard let onlySchoolId = destinationSchoolIds.only else { return [] }
        return model.childrenBySchool[onlySchoolId] ?? []
    }
    private var errorMessage: String? { validationError ?? model.errorMessage }

    private var eligibleMembers: [SchoolMember] {
        return members.filter {
            let policy = AssignmentAccessPolicy(
                context: appSession.accessContext(selectedSchoolId: $0.membership.schoolId)
            )
            return policy.canAssign(
                to: $0.id,
                role: $0.membership.role,
                accessState: $0.membership.accessState,
                category: category
            )
        }
    }

    private var eligibleMemberOptions: [AssignmentMemberOption] {
        eligibleMembers.map { member in
            AssignmentMemberOption(
                member: member,
                schoolName: schools.first { $0.id == member.membership.schoolId }?.name
            )
        }
    }

    private var selectedMembers: [AssignmentMemberOption] {
        eligibleMemberOptions
            .filter { selectedRecipientKeys.contains($0.id) }
            .sorted { $0.sortKey < $1.sortKey }
    }

    private var suggestions: [AssignmentMemberOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return eligibleMemberOptions
            .filter { !selectedRecipientKeys.contains($0.id) }
            .filter {
                $0.member.displayName.lowercased().contains(query)
                    || $0.schoolName?.lowercased().contains(query) == true
            }
            .sorted { score($0.member.displayName, query: query) < score($1.member.displayName, query: query) }
            .prefix(5)
            .map { $0 }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && destinationSchoolIds.isEmpty == false
            && deliverableSchoolIds.isEmpty == false
            && !model.isSaving
    }

    private var resolvedRecipientIds: [UUID] {
        destinationSchoolIds.flatMap { resolvedRecipientIds(for: $0) }
    }

    private func resolvedRecipientIds(for schoolId: UUID) -> [UUID] {
        let schoolMembers = eligibleMembers.filter { $0.membership.schoolId == schoolId }
        switch audienceMode {
        case .people:
            return schoolMembers
                .filter {
                    selectedRecipientKeys.contains(AssignmentRecipientSelectionKey(
                        schoolId: schoolId,
                        userId: $0.id
                    ))
                }
                .map(\.id)
        case .role:
            return schoolMembers
                .filter { $0.membership.role == selectedAudienceRole }
                .map(\.id)
        case .school:
            return schoolMembers.map(\.id)
        case .child:
            return []
        }
    }

    private var deliverableSchoolIds: [UUID] {
        if audienceMode == .child {
            return selectedChildId == nil ? [] : destinationSchoolIds
        }
        return destinationSchoolIds.filter { resolvedRecipientIds(for: $0).isEmpty == false }
    }

    private var eligibleRoles: [SchoolRole] {
        SchoolRole.allCases.filter { role in
            eligibleMembers.contains { $0.membership.role == role }
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .what:
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .audience:
            return destinationSchoolIds.isEmpty == false
                && deliverableSchoolIds.isEmpty == false
        case .materials:
            return true
        case .schedule:
            let releaseDate = publication == .scheduled ? publishAt : Date()
            let scheduleIsValid = publication != .scheduled || publishAt > Date()
            let dueDateIsValid = hasDueDate == false || dueAt > releaseDate
            return scheduleIsValid && dueDateIsValid
        case .preview:
            return canSave
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        ForEach(AssignmentComposerStep.allCases) { item in
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(item.rawValue <= step.rawValue ? AppConstants.Colors.accessibleYellow : Color.gray.opacity(0.3))
                                    .frame(width: 24, height: 24)
                                    .overlay(Text("\(item.rawValue + 1)").font(.caption2.bold()).foregroundColor(AppConstants.Colors.brandNavy))
                                Text(item.shortTitle)
                                    .font(.caption2)
                                    .foregroundColor(item == step ? AppConstants.Colors.accessibleYellow : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                switch step {
                case .what:
                    Section("What") {
                    TextField("Title", text: $title)
                    TextField("Instructions", text: $description, axis: .vertical)
                    Picker("Type", selection: $category) {
                        ForEach(availableCategories) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    }
                    schoolTargetSection
                case .audience:
                    Section("Audience") {
                        Picker("Audience", selection: $audienceMode) {
                            ForEach(AssignmentAudienceMode.available(
                                hasChildren: children.isEmpty == false,
                                allowsChildSelection: isMultiSchoolAudience == false
                            )) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if audienceMode == .role {
                            Picker("Role", selection: $selectedAudienceRole) {
                                ForEach(eligibleRoles) { role in
                                    Text(role.title).tag(role)
                                }
                            }
                            Text("\(resolvedRecipientIds.count) matching recipient\(resolvedRecipientIds.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if audienceMode == .school {
                            Text("All \(eligibleMembers.count) eligible members across \(destinationSchoolCountText) will receive the assignment.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if audienceMode == .child {
                            Picker("Child", selection: $selectedChildId) {
                                Text("Select a child").tag(Optional<UUID>.none)
                                ForEach(children) { child in
                                    Text(child.fullName).tag(Optional(child.id))
                                }
                            }
                            Text("The child’s active guardians will receive this work.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            peoplePicker
                        }

                        if destinationSchoolIds.count > 1 {
                            Text("Each school receives its own assignment, recipient list, notifications, and review history.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        skippedSchoolsWarning
                    }
                case .materials:
                    Section("Materials") {
                    Picker("Material Type", selection: $materialType) {
                        Text("Article").tag("article")
                        Text("Link").tag("link")
                        Text("Picture").tag("image")
                        Text("Video").tag("video")
                        Text("File").tag("file")
                        Text("Mixed").tag("mixed")
                    }
                    TextField("Article/video/link URL", text: $materialURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Add Link") { addMaterialURL() }
                        .disabled(materialURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(materialURLs, id: \.self) { url in
                        HStack {
                            Text(url).lineLimit(1)
                            Spacer()
                            Button("Remove") { materialURLs.removeAll { $0 == url } }
                        }
                    }
                    Menu {
                        ForEach(AssignmentFileImportSource.allCases) { source in
                            Button {
                                showingMaterialImporter = true
                            } label: {
                                Label(source.title, systemImage: source.systemImage)
                            }
                        }
                    } label: {
                        Label(
                            selectedMaterialFileURLs.isEmpty ? "Add Materials" : "Add More Materials",
                            systemImage: "paperclip"
                        )
                    }
                    .accessibilityIdentifier("assignment-material-source-menu")
                    if let help = AssignmentFileImportSource.googleDrive.pickerHelp {
                        Text(help)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach(selectedMaterialFileURLs, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent).lineLimit(1)
                            Spacer()
                            Button("Remove") { removeMaterialFile(url) }
                        }
                    }
                    if materialURLs.isEmpty && selectedMaterialFileURLs.isEmpty {
                        Text("Materials are optional. Add as many links or files as the assignment needs.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                case .schedule:
                    Section("Schedule") {
                        Picker("Status", selection: $publication) {
                            ForEach(AssignmentPublicationChoice.allCases) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        if publication == .scheduled {
                            DatePicker("Publish", selection: $publishAt, in: Date()...)
                        }
                        Toggle("Due date", isOn: $hasDueDate)
                        if hasDueDate {
                            DatePicker("Due", selection: $dueAt)
                            if canAdvance == false {
                                Text("The due date must be after the assignment is published.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                case .preview:
                    Section("Preview") {
                        LabeledContent("Title", value: title)
                        LabeledContent("Type", value: category.title)
                        LabeledContent("Schools", value: schoolSummary)
                        LabeledContent("Audience", value: audienceSummary)
                        LabeledContent("Materials", value: "\(materialURLs.count + selectedMaterialFileURLs.count)")
                        LabeledContent("Status", value: publication.title)
                        if description.isEmpty == false {
                            Text(description)
                        }
                        ForEach(materialURLs, id: \.self) { value in
                            if let url = URL(string: value) {
                                AssignmentLinkPreview(url: url)
                                    .frame(height: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture { webURL = url }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        if step != .what {
                            Button("Back") { step = step.previous }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("assignment-composer-back")
                        }
                        Spacer()
                        if step != .preview {
                            Button("Next") { step = step.next }
                                .buttonStyle(.borderedProminent)
                                .disabled(canAdvance == false)
                                .accessibilityIdentifier("assignment-composer-next")
                        } else {
                            Button(publication.actionTitle) { save() }
                                .buttonStyle(.borderedProminent)
                                .disabled(canSave == false)
                                .accessibilityIdentifier("assignment-composer-save")
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Assignment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        removeAllMaterialFiles()
                        dismiss()
                    }
                    .disabled(model.isSaving)
                }
            }
            .task { await loadOptions() }
            .fileImporter(isPresented: $showingMaterialImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                do {
                    guard let ownerId = appSession.profile?.id else {
                        validationError = "Could not attach the selected material because your account is unavailable."
                        return
                    }
                    let importedURLs = try materialDraftStore.add(
                        try result.get(),
                        for: materialDraftId,
                        ownerId: ownerId
                    )
                    selectedMaterialFileURLs.append(contentsOf: importedURLs)
                    validationError = nil
                } catch where AppErrorMessage.isCancellation(error) {
                } catch {
                    validationError = AppErrorMessage.school("Could not attach the selected material", error)
                }
            }
            .sheet(isPresented: Binding(
                get: { webURL != nil },
                set: { if !$0 { webURL = nil } }
            )) {
                if let webURL { AssignmentSafariView(url: webURL).ignoresSafeArea() }
            }
            .onChange(of: category) { _, _ in
                selectedRecipientKeys = selectedRecipientKeys.intersection(Set(eligibleMemberOptions.map(\.id)))
                if eligibleRoles.contains(selectedAudienceRole) == false {
                    selectedAudienceRole = eligibleRoles.first ?? .teacher
                }
            }
            .onChange(of: schoolTarget) { _, _ in normalizeSchoolTarget() }
            .onChange(of: selectedSchoolId) { _, _ in normalizeSchoolTarget() }
            .onChange(of: selectedSchoolIds) { _, _ in normalizeSchoolTarget() }
            .interactiveDismissDisabled(model.isSaving)
            .onDisappear { removeAllMaterialFiles() }
        }
    }

    @ViewBuilder
    private var schoolTargetSection: some View {
        if supportsMultipleSchools {
            Section("Schools") {
                Picker("Send To", selection: $schoolTarget) {
                    ForEach(AssignmentSchoolTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("assignment-school-target")

                if schoolTarget == .one {
                    Picker("School", selection: $selectedSchoolId) {
                        ForEach(schools) { school in
                            Text(school.name).tag(school.id)
                        }
                    }
                } else if schoolTarget == .selected {
                    ForEach(schools) { school in
                        Toggle(school.name, isOn: Binding(
                            get: { selectedSchoolIds.contains(school.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedSchoolIds.insert(school.id)
                                } else {
                                    selectedSchoolIds.remove(school.id)
                                }
                            }
                        ))
                        .accessibilityIdentifier("assignment-school-\(school.id.uuidString)")
                    }
                }

                Text("\(destinationSchoolCountText) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var peoplePicker: some View {
        Button("Select All Eligible") {
            selectedRecipientKeys.formUnion(eligibleMemberOptions.map(\.id))
        }
        if selectedMembers.isEmpty == false {
            ForEach(selectedMembers) { option in
                HStack {
                    Text(option.label(includesSchool: isMultiSchoolAudience))
                    Spacer()
                    Button("Remove") { selectedRecipientKeys.remove(option.id) }
                }
            }
        }
        TextField(isMultiSchoolAudience ? "Search people or schools" : "Search people", text: $searchText)
        ForEach(suggestions) { option in
            Button {
                selectedRecipientKeys.insert(option.id)
                searchText = ""
            } label: {
                HStack {
                    Text(option.label(includesSchool: isMultiSchoolAudience))
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
    }

    private var audienceSummary: String {
        switch audienceMode {
        case .people: "\(resolvedRecipientIds.count) people"
        case .role: "\(selectedAudienceRole.title) · \(resolvedRecipientIds.count) people"
        case .school: "\(resolvedRecipientIds.count) people"
        case .child: children.first(where: { $0.id == selectedChildId })?.fullName ?? "No child selected"
        }
    }

    private var schoolSummary: String {
        if destinationSchoolIds.count == 1 {
            return schools.first { $0.id == destinationSchoolIds[0] }?.name ?? "1 school"
        }
        if skippedSchools.isEmpty {
            return "\(destinationSchoolIds.count) schools"
        }
        return "\(deliverableSchoolIds.count) of \(destinationSchoolIds.count) selected schools"
    }

    private var destinationSchoolCountText: String {
        destinationSchoolIds.count == 1 ? "1 school" : "\(destinationSchoolIds.count) schools"
    }

    private var skippedSchools: [School] {
        guard audienceMode != .child else { return [] }
        return schools.filter {
            destinationSchoolIds.contains($0.id) && resolvedRecipientIds(for: $0.id).isEmpty
        }
    }

    @ViewBuilder
    private var skippedSchoolsWarning: some View {
        if skippedSchools.count == 1, let school = skippedSchools.first {
            Text("\(school.name) has no \(missingRecipientDescription) and will be skipped.")
                .font(.caption)
                .foregroundColor(.orange)
        } else if skippedSchools.count > 1 {
            DisclosureGroup("\(skippedSchools.count) schools have no \(missingRecipientDescription) and will be skipped") {
                ForEach(skippedSchools) { school in
                    Text(school.name)
                        .font(.caption)
                }
            }
            .font(.caption)
            .foregroundColor(.orange)
        }
    }

    private var missingRecipientDescription: String {
        switch audienceMode {
        case .people: "selected recipients"
        case .role: "eligible \(selectedAudienceRole.title.lowercased()) recipients"
        case .school: "eligible recipients"
        case .child: "eligible guardians"
        }
    }

    private func addMaterialURL() {
        let value = materialURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false, materialURLs.contains(value) == false else { return }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            validationError = "Material links must be complete http:// or https:// URLs."
            return
        }
        materialURLs.append(value)
        materialURL = ""
        validationError = nil
    }

    private func removeMaterialFile(_ url: URL) {
        guard let ownerId = appSession.profile?.id else { return }
        do {
            try materialDraftStore.remove(url, for: materialDraftId, ownerId: ownerId)
            selectedMaterialFileURLs.removeAll { $0 == url }
        } catch {
            validationError = AppErrorMessage.school("Could not remove the attached material", error)
        }
    }

    private func removeAllMaterialFiles() {
        guard let ownerId = appSession.profile?.id else { return }
        try? materialDraftStore.removeAll(for: materialDraftId, ownerId: ownerId)
        selectedMaterialFileURLs = []
    }

    private func score(_ name: String, query: String) -> Int {
        let lower = name.lowercased()
        if lower.hasPrefix(query) { return 0 }
        if lower.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 1 }
        return 2
    }

    @MainActor
    private func loadOptions() async {
        await model.load(schoolIds: schools.isEmpty ? [schoolId] : schools.map(\.id))
        selectedAudienceRole = eligibleRoles.first ?? .teacher
    }

    private func normalizeSchoolTarget() {
        selectedRecipientKeys = Set(selectedRecipientKeys.filter {
            destinationSchoolIds.contains($0.schoolId)
        })
        if isMultiSchoolAudience && audienceMode == .child {
            selectedChildId = nil
            audienceMode = .people
        }
        if eligibleRoles.contains(selectedAudienceRole) == false {
            selectedAudienceRole = eligibleRoles.first ?? .teacher
        }
    }

    private func save() {
        validationError = nil
        Task {
            let drafts = deliverableSchoolIds.map { destinationSchoolId in
                AssignmentDraft(
                    schoolId: destinationSchoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    category: category,
                    audienceRole: inferredAudienceRole,
                    childId: audienceMode == .child ? selectedChildId : nil,
                    dueAt: hasDueDate ? dueAt : nil,
                    recipientIds: resolvedRecipientIds(for: destinationSchoolId),
                    materialURLs: materialURLs,
                    materialType: materialType,
                    materialFileURLs: selectedMaterialFileURLs,
                    status: publication.status,
                    publishAt: publication == .scheduled ? publishAt : nil,
                    idempotencyKey: "\(mutationKey)-\(destinationSchoolId.uuidString)"
                )
            }
            let saved = await model.save(drafts)
            if saved {
                removeAllMaterialFiles()
                onSaved()
                dismiss()
            }
        }
    }

    private var inferredAudienceRole: SchoolRole? {
        if audienceMode == .role { return selectedAudienceRole }
        switch category {
        case .training, .curriculum:
            let policy = AssignmentAccessPolicy(
                context: appSession.accessContext(selectedSchoolId: selectedSchoolId)
            )
            return policy.canTargetMultipleStaffRoles ? nil : .teacher
        case .paperwork, .onboarding, .childRecord, .compliance, .general:
            return nil
        }
    }
}

private enum AssignmentComposerStep: Int, CaseIterable, Identifiable {
    case what
    case audience
    case materials
    case schedule
    case preview

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .what: "What"
        case .audience: "Audience"
        case .materials: "Materials"
        case .schedule: "Schedule"
        case .preview: "Preview"
        }
    }

    var next: AssignmentComposerStep {
        AssignmentComposerStep(rawValue: min(rawValue + 1, AssignmentComposerStep.preview.rawValue)) ?? .preview
    }

    var previous: AssignmentComposerStep {
        AssignmentComposerStep(rawValue: max(rawValue - 1, AssignmentComposerStep.what.rawValue)) ?? .what
    }
}

private enum AssignmentAudienceMode: String, CaseIterable, Identifiable {
    case people
    case role
    case school
    case child

    var id: String { rawValue }

    var title: String {
        switch self {
        case .people: "People"
        case .role: "Role"
        case .school: "School"
        case .child: "Child"
        }
    }

    static func available(hasChildren: Bool, allowsChildSelection: Bool) -> [AssignmentAudienceMode] {
        allCases.filter { mode in
            (hasChildren || mode != .child)
                && (allowsChildSelection || mode != .child)
        }
    }
}

struct AssignmentRecipientSelectionKey: Hashable {
    let schoolId: UUID
    let userId: UUID
}

struct AssignmentMemberOption: Identifiable {
    let member: SchoolMember
    let schoolName: String?

    var id: AssignmentRecipientSelectionKey {
        AssignmentRecipientSelectionKey(
            schoolId: member.membership.schoolId,
            userId: member.id
        )
    }

    var sortKey: String {
        member.displayName.lowercased() + "-" + (schoolName?.lowercased() ?? "")
    }

    func label(includesSchool: Bool) -> String {
        let person = "\(member.displayName) · \(member.membership.role.title)"
        guard includesSchool, let schoolName else { return person }
        return "\(person) · \(schoolName)"
    }
}

private enum AssignmentSchoolTarget: String, CaseIterable, Identifiable {
    case one
    case selected
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: "One"
        case .selected: "Choose"
        case .all: "All"
        }
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}

private enum AssignmentPublicationChoice: String, CaseIterable, Identifiable {
    case draft
    case scheduled
    case published

    var id: String { rawValue }
    var status: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .scheduled: "Scheduled"
        case .published: "Published"
        }
    }

    var actionTitle: String {
        switch self {
        case .draft: "Save Draft"
        case .scheduled: "Schedule"
        case .published: "Publish"
        }
    }
}
