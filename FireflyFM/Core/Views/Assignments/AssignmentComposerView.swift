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
    let defaultCategory: AssignmentCategory
    var onSaved: () -> Void

    @State private var model = AssignmentComposerModel()
    @State private var title = ""
    @State private var description = ""
    @State private var category: AssignmentCategory
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
    @State private var selectedRecipientIds = Set<UUID>()
    @State private var selectedChildId: UUID?
    @State private var searchText = ""
    @State private var mutationKey = UUID().uuidString
    @State private var validationError: String?

    init(filter: AssignmentFilter, schoolId: UUID, defaultCategory: AssignmentCategory, onSaved: @escaping () -> Void) {
        self.filter = filter
        self.schoolId = schoolId
        self.defaultCategory = defaultCategory
        self.onSaved = onSaved
        _category = State(initialValue: defaultCategory)
    }

    private var availableCategories: [AssignmentCategory] {
        filter.categories ?? AssignmentCategory.allCases
    }

    private var members: [SchoolMember] { model.members }
    private var children: [Child] { model.children }
    private var errorMessage: String? { validationError ?? model.errorMessage }

    private var eligibleMembers: [SchoolMember] {
        let policy = AssignmentAccessPolicy(
            context: appSession.accessContext(selectedSchoolId: schoolId)
        )
        return members.filter { policy.canAssign(to: $0.membership.role, category: category) }
    }

    private var selectedMembers: [SchoolMember] {
        eligibleMembers
            .filter { selectedRecipientIds.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var suggestions: [SchoolMember] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return eligibleMembers
            .filter { !selectedRecipientIds.contains($0.id) }
            .filter { $0.displayName.lowercased().contains(query) }
            .sorted { score($0.displayName, query: query) < score($1.displayName, query: query) }
            .prefix(5)
            .map { $0 }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!resolvedRecipientIds.isEmpty || selectedChildId != nil)
            && !model.isSaving
    }

    private var resolvedRecipientIds: [UUID] {
        switch audienceMode {
        case .people:
            return Array(selectedRecipientIds)
        case .role:
            return eligibleMembers
                .filter { $0.membership.role == selectedAudienceRole }
                .map(\.id)
        case .school:
            return eligibleMembers.map(\.id)
        case .child:
            return []
        }
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
            return resolvedRecipientIds.isEmpty == false || selectedChildId != nil
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
                case .audience:
                    Section("Audience") {
                        Picker("Audience", selection: $audienceMode) {
                            ForEach(AssignmentAudienceMode.available(hasChildren: children.isEmpty == false)) { mode in
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
                            Text("All \(eligibleMembers.count) eligible members of this school will receive the assignment.")
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
                    Button(selectedMaterialFileURLs.isEmpty ? "Attach files, pictures, or videos" : "Add More Files") {
                        showingMaterialImporter = true
                    }
                    ForEach(selectedMaterialFileURLs, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent).lineLimit(1)
                            Spacer()
                            Button("Remove") { selectedMaterialFileURLs.removeAll { $0 == url } }
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
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadOptions() }
            .fileImporter(isPresented: $showingMaterialImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if let urls = try? result.get() {
                    selectedMaterialFileURLs.append(contentsOf: urls.filter { selectedMaterialFileURLs.contains($0) == false })
                }
            }
            .sheet(isPresented: Binding(
                get: { webURL != nil },
                set: { if !$0 { webURL = nil } }
            )) {
                if let webURL { AssignmentSafariView(url: webURL).ignoresSafeArea() }
            }
            .onChange(of: category) { _, _ in
                selectedRecipientIds = selectedRecipientIds.intersection(Set(eligibleMembers.map(\.id)))
                if eligibleRoles.contains(selectedAudienceRole) == false {
                    selectedAudienceRole = eligibleRoles.first ?? .teacher
                }
            }
        }
    }

    @ViewBuilder
    private var peoplePicker: some View {
        Button("Select All Eligible") {
            selectedRecipientIds.formUnion(eligibleMembers.map(\.id))
        }
        if selectedMembers.isEmpty == false {
            ForEach(selectedMembers) { member in
                HStack {
                    Text("\(member.displayName) · \(member.membership.role.title)")
                    Spacer()
                    Button("Remove") { selectedRecipientIds.remove(member.id) }
                }
            }
        }
        TextField("Search people", text: $searchText)
        ForEach(suggestions) { member in
            Button {
                selectedRecipientIds.insert(member.id)
                searchText = ""
            } label: {
                HStack {
                    Text("\(member.displayName) · \(member.membership.role.title)")
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
    }

    private var audienceSummary: String {
        switch audienceMode {
        case .people: "\(resolvedRecipientIds.count) people"
        case .role: "\(selectedAudienceRole.title) · \(resolvedRecipientIds.count)"
        case .school: "School · \(resolvedRecipientIds.count)"
        case .child: children.first(where: { $0.id == selectedChildId })?.fullName ?? "No child selected"
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

    private func score(_ name: String, query: String) -> Int {
        let lower = name.lowercased()
        if lower.hasPrefix(query) { return 0 }
        if lower.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 1 }
        return 2
    }

    @MainActor
    private func loadOptions() async {
        await model.load(schoolId: schoolId)
        selectedAudienceRole = eligibleRoles.first ?? .teacher
    }

    private func save() {
        validationError = nil
        Task {
            let saved = await model.save(AssignmentDraft(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    category: category,
                    audienceRole: inferredAudienceRole,
                    childId: audienceMode == .child ? selectedChildId : nil,
                    dueAt: hasDueDate ? dueAt : nil,
                    recipientIds: resolvedRecipientIds,
                    materialURLs: materialURLs,
                    materialType: materialType,
                    materialFileURLs: selectedMaterialFileURLs,
                    status: publication.status,
                    publishAt: publication == .scheduled ? publishAt : nil,
                    idempotencyKey: mutationKey
                ))
            if saved {
                onSaved()
                dismiss()
            }
        }
    }

    private var inferredAudienceRole: SchoolRole? {
        if audienceMode == .role { return selectedAudienceRole }
        switch category {
        case .paperwork, .onboarding, .childRecord:
            return .parent
        case .training, .curriculum:
            let policy = AssignmentAccessPolicy(
                context: appSession.accessContext(selectedSchoolId: schoolId)
            )
            return policy.canTargetMultipleStaffRoles ? nil : .teacher
        case .compliance, .general:
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

    static func available(hasChildren: Bool) -> [AssignmentAudienceMode] {
        hasChildren ? allCases : allCases.filter { $0 != .child }
    }
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
