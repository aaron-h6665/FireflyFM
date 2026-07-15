//
//  AssignmentsView.swift
//  FireflyFM
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum AssignmentSurface: Hashable {
    case all
    case paperwork
    case curriculum
    case documents
    case hqEducation

    var title: String {
        switch self {
        case .all: "Assignments"
        case .paperwork: "Paperwork"
        case .curriculum: "Curriculum & Training"
        case .documents: "Documents"
        case .hqEducation: "Education"
        }
    }

    var subtitle: String {
        switch self {
        case .all: "Assignments, submissions, and review status."
        case .paperwork: "Forms, contracts, child paperwork, and parent submissions."
        case .curriculum: "Training and curriculum assignments with read checks and feedback."
        case .documents: "Onboarding, certificates, licenses, and compliance documents."
        case .hqEducation: "Assign training and curriculum to teachers and school directors."
        }
    }

    var categories: [AssignmentCategory]? {
        switch self {
        case .all:
            nil
        case .paperwork:
            [.paperwork, .onboarding, .childRecord]
        case .curriculum:
            [.training, .curriculum]
        case .documents:
            [.onboarding, .compliance]
        case .hqEducation:
            [.training, .curriculum, .compliance, .general]
        }
    }

    var defaultCategory: AssignmentCategory {
        switch self {
        case .paperwork: .paperwork
        case .curriculum, .hqEducation: .training
        case .documents: .onboarding
        case .all: .general
        }
    }
}

struct AssignmentsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    let surface: AssignmentSurface

    @State private var schools: [School] = []
    @State private var selectedSchoolId: UUID?
    @State private var inboxItems: [AssignmentInboxItem] = []
    @State private var reviewItems: [AssignmentInboxItem] = []
    @State private var selectedTab: AssignmentListTab = .toDo
    @State private var showingComposer = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canCreate: Bool {
        appSession.role?.canManageSchool == true
    }

    private var needsSchoolPicker: Bool {
        appSession.role == .hqDirector && surface == .hqEducation
    }

    private var effectiveSchoolId: UUID? {
        needsSchoolPicker ? selectedSchoolId : appSession.activeSchool?.id
    }

    private var visibleTabs: [AssignmentListTab] {
        appSession.role?.canManageSchool == true
            ? AssignmentListTab.allCases
            : AssignmentListTab.allCases.filter { $0 != .reviewQueue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        schoolPicker
                        tabPicker

                        if isLoading {
                            ProgressView()
                                .tint(AppConstants.Colors.accessibleYellow)
                        } else if displayedItems.isEmpty {
                            emptyPanel("No assignments in this section yet.")
                        } else {
                            ForEach(displayedItems) { item in
                                NavigationLink {
                                    AssignmentDetailView(assignmentId: item.assignmentId) {
                                        Task { await loadAssignments() }
                                    }
                                } label: {
                                    AssignmentCardView(item: item, isReviewQueue: selectedTab == .reviewQueue)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(surface.title)
            .toolbar {
                if canCreate {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingComposer = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingComposer) {
                if let schoolId = effectiveSchoolId {
                    AssignmentComposerView(
                        surface: surface,
                        schoolId: schoolId,
                        defaultCategory: surface.defaultCategory
                    ) {
                        Task { await loadAssignments() }
                    }
                }
            }
            .task { await loadInitialData() }
            .refreshable { await loadAssignments() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(surface.title)
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text(surface.subtitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var schoolPicker: some View {
        if needsSchoolPicker {
            Picker("School", selection: Binding(
                get: { selectedSchoolId ?? schools.first?.id },
                set: { selectedSchoolId = $0 }
            )) {
                ForEach(schools) { school in
                    Text(school.name).tag(Optional(school.id))
                }
            }
            .pickerStyle(.menu)
            .tint(AppConstants.Colors.accessibleYellow)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppConstants.Colors.card)
            .cornerRadius(10)
            .onChange(of: selectedSchoolId) { _, _ in
                Task { await loadAssignments() }
            }
        }
    }

    private var tabPicker: some View {
        Picker("Assignments", selection: $selectedTab) {
            ForEach(visibleTabs) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var displayedItems: [AssignmentInboxItem] {
        let now = Date()
        switch selectedTab {
        case .toDo:
            return inboxItems.filter { item in
                item.dueAt.map { $0 >= now } ?? true
                    && ![.submitted, .reviewed, .accepted, .flagged].contains(item.completionStatus)
            }
        case .submitted:
            return inboxItems.filter { $0.completionStatus == .submitted }
        case .reviewed:
            return inboxItems.filter { [.reviewed, .accepted, .flagged].contains($0.completionStatus) }
        case .pastDue:
            return inboxItems.filter { item in
                item.dueAt.map { $0 < now } ?? false
                    && ![.submitted, .reviewed, .accepted].contains(item.completionStatus)
            }
        case .reviewQueue:
            return reviewItems
        }
    }

    private func emptyPanel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
    }

    @MainActor
    private func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        do {
            if needsSchoolPicker {
                schools = try await SchoolService.shared.fetchSchoolsForHQ()
                if selectedSchoolId == nil {
                    selectedSchoolId = schools.first?.id
                }
            }
            await loadAssignments()
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = AppErrorMessage.school("Could not load schools", error)
        }
    }

    @MainActor
    private func loadAssignments() async {
        guard let schoolId = effectiveSchoolId else {
            inboxItems = []
            reviewItems = []
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let loadedInbox = SchoolWorkflowService.shared.fetchAssignmentInbox(
                schoolId: schoolId,
                categories: surface.categories
            )
            async let loadedReview = appSession.role?.canManageSchool == true
                ? SchoolWorkflowService.shared.fetchAssignmentReviewQueue(schoolId: schoolId, categories: surface.categories)
                : []
            inboxItems = try await loadedInbox
            reviewItems = try await loadedReview
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load assignments", error)
            isLoading = false
        }
    }
}

private enum AssignmentListTab: String, CaseIterable, Identifiable {
    case toDo
    case submitted
    case reviewed
    case pastDue
    case reviewQueue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toDo: "To Do"
        case .submitted: "Submitted"
        case .reviewed: "Reviewed"
        case .pastDue: "Past Due"
        case .reviewQueue: "Review"
        }
    }
}

private struct AssignmentCardView: View {
    let item: AssignmentInboxItem
    let isReviewQueue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundColor(.white.opacity(0.62))
                    }
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 8) {
                Label(item.category.title, systemImage: icon)
                if let dueAt = item.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                }
                if let childName = item.childDisplayName {
                    Label(childName, systemImage: "figure.child")
                }
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.58))

            if isReviewQueue {
                Text("\(item.submissionCount) submitted · \(item.recipientCount) assigned · \(item.materialCount) material\(item.materialCount == 1 ? "" : "s")")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private var statusBadge: some View {
        Text(item.completionStatus.title)
            .font(.caption.bold())
            .foregroundColor(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12))
            .cornerRadius(8)
    }

    private var statusColor: Color {
        switch item.completionStatus {
        case .accepted: .green
        case .flagged, .overdue: .red
        case .submitted, .reviewed: .orange
        case .read: AppConstants.Colors.accessibleYellow
        case .notStarted: .white.opacity(0.68)
        }
    }

    private var icon: String {
        switch item.category {
        case .paperwork: "doc.text.fill"
        case .training: "graduationcap.fill"
        case .curriculum: "books.vertical.fill"
        case .onboarding: "person.crop.circle.badge.checkmark"
        case .childRecord: "figure.child"
        case .compliance: "checkmark.seal.fill"
        case .general: "tray.full.fill"
        }
    }
}

struct AssignmentDetailView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    let assignmentId: UUID
    var onChanged: () -> Void = {}

    @State private var bundle: AssignmentDetailBundle?
    @State private var profilesById: [UUID: UserProfile] = [:]
    @State private var currentUserId: UUID?
    @State private var feedbackText = ""
    @State private var selectedFileURL: URL?
    @State private var showingImporter = false
    @State private var reviewMessage = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var assignment: Assignment? { bundle?.assignment }

    private var mySubmission: AssignmentSubmission? {
        guard let currentUserId else { return nil }
        return bundle?.submissions.first { $0.submittedBy == currentUserId }
    }

    private var isRead: Bool {
        guard let currentUserId else { return false }
        return bundle?.readReceipts.contains { $0.userId == currentUserId } == true
    }

    private var canSubmit: Bool {
        guard let currentUserId, let bundle else { return false }
        return bundle.recipients.contains { $0.userId == currentUserId }
            || (appSession.role == .parent && bundle.assignment.childId != nil)
    }

    private var canReview: Bool {
        guard let currentUserId, let bundle else { return false }
        let isRecipient = bundle.recipients.contains { $0.userId == currentUserId }
        let hasOwnSubmission = bundle.submissions.contains { $0.submittedBy == currentUserId }
        guard !isRecipient && !hasOwnSubmission else { return false }

        if appSession.role == .hqDirector {
            return true
        }
        if appSession.role == .schoolDirector {
            return bundle.assignment.assignedBy == currentUserId || bundle.assignment.assignedBy == nil
        }
        return false
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    } else if let bundle {
                        header(bundle.assignment)
                        materialsSection(bundle.materials)
                        readSection
                        if canSubmit {
                            submitSection(bundle.assignment)
                        }
                        if canReview {
                            reviewSection(bundle)
                        }
                        feedbackSection(bundle)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            selectedFileURL = try? result.get().first
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(assignment.category.title)
                    .font(.caption.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppConstants.Colors.accessibleYellow)
                    .cornerRadius(8)
                Spacer()
                if let dueAt = assignment.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.68))
                }
            }
            Text(assignment.title)
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            if let description = assignment.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.72))
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func materialsSection(_ materials: [AssignmentMaterial]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Materials")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            if materials.isEmpty {
                smallPanel("No materials attached.")
            } else {
                ForEach(materials) { material in
                    HStack {
                        Label(material.title ?? material.fileName ?? material.url ?? "Material", systemImage: materialIcon(material))
                            .foregroundColor(.white)
                        Spacer()
                        if material.privateFilePath != nil {
                            Button("Open") { openFile(path: material.privateFilePath) }
                        }
                        if let url = material.url, !url.isEmpty {
                            Button("Link") { openLink(url) }
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .tint(AppConstants.Colors.accessibleYellow)
                    .padding()
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                }
            }
        }
    }

    private var readSection: some View {
        Button {
            markRead()
        } label: {
            Label(isRead ? "Read" : "Check After Reading", systemImage: isRead ? "checkmark.circle.fill" : "circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRead ? .green : AppConstants.Colors.accessibleYellow)
        .disabled(isRead || isSaving)
    }

    private func submitSection(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Submission")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            if let mySubmission {
                Text("Submitted \(mySubmission.submittedAt?.formatted(date: .abbreviated, time: .shortened) ?? ""). Status: \(mySubmission.status.capitalized).")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.62))
                if let message = mySubmission.reviewerMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.72))
                        .padding(8)
                        .background(AppConstants.Colors.background.opacity(0.45))
                        .cornerRadius(8)
                }
            }

            TextEditor(text: $feedbackText)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .foregroundColor(.white)
                .padding(8)
                .background(AppConstants.Colors.card)
                .cornerRadius(8)

            Button(selectedFileURL?.lastPathComponent ?? "Attach file, photo, or video") {
                showingImporter = true
            }
            .buttonStyle(.bordered)
            .tint(AppConstants.Colors.accessibleYellow)

            Button(mySubmission == nil ? "Submit Assignment" : "Replace Submission") {
                submit(assignment)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppConstants.Colors.accessibleYellow)
            .disabled(isSaving || (selectedFileURL == nil && feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
        .padding()
        .background(AppConstants.Colors.card.opacity(0.72))
        .cornerRadius(8)
    }

    private func reviewSection(_ bundle: AssignmentDetailBundle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Queue")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            if bundle.submissions.isEmpty {
                smallPanel("No submissions yet.")
            } else {
                TextField("Optional review message", text: $reviewMessage, axis: .vertical)
                    .padding(12)
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .tint(AppConstants.Colors.accessibleYellow)

                ForEach(bundle.submissions) { submission in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profilesById[submission.submittedBy]?.displayName ?? "Submitted user")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Status: \(submission.status.capitalized)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.58))
                        ForEach(bundle.attachments.filter { $0.submissionId == submission.id }) { attachment in
                            Button {
                                openFile(path: attachment.privateFilePath)
                            } label: {
                                Label(attachment.fileName ?? "Attachment", systemImage: "paperclip")
                            }
                            .buttonStyle(.bordered)
                            .tint(AppConstants.Colors.accessibleYellow)
                        }
                        HStack {
                            Button("Accept") { review(submission, status: "accepted") }
                            Button("Flag") { review(submission, status: "flagged") }
                        }
                        .buttonStyle(.bordered)
                        .tint(AppConstants.Colors.accessibleYellow)
                    }
                    .padding()
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                }
            }
        }
    }

    private func feedbackSection(_ bundle: AssignmentDetailBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feedback")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            if bundle.feedbackMessages.isEmpty {
                smallPanel("No feedback messages yet.")
            } else {
                ForEach(bundle.feedbackMessages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profilesById[message.senderId]?.displayName ?? "School member")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.68))
                        Text(message.body)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                }
            }
        }
    }

    private func smallPanel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            currentUserId = try await ProfileService.shared.currentUserId()
            let loaded = try await SchoolWorkflowService.shared.fetchAssignmentDetail(assignmentId: assignmentId)
            bundle = loaded
            let profileIds = Set(loaded.submissions.map(\.submittedBy) + loaded.feedbackMessages.map(\.senderId))
            profilesById = try await ProfileService.shared.fetchProfiles(ids: Array(profileIds))
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load assignment", error)
            isLoading = false
        }
    }

    private func markRead() {
        Task {
            do {
                try await SchoolWorkflowService.shared.markAssignmentRead(assignmentId: assignmentId)
                await load()
                onChanged()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not mark assignment read", error)
                }
            }
        }
    }

    private func submit(_ assignment: Assignment) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.submitAssignment(
                    assignment: assignment,
                    fileURL: selectedFileURL,
                    feedbackText: feedbackText
                )
                await MainActor.run {
                    selectedFileURL = nil
                    feedbackText = ""
                    isSaving = false
                }
                await load()
                onChanged()
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not submit assignment", error)
                }
            }
        }
    }

    private func review(_ submission: AssignmentSubmission, status: String) {
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.reviewAssignmentSubmission(
                    submissionId: submission.id,
                    status: status,
                    message: reviewMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reviewMessage
                )
                await MainActor.run { reviewMessage = "" }
                await load()
                onChanged()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not review assignment", error)
                }
            }
        }
    }

    private func materialIcon(_ material: AssignmentMaterial) -> String {
        switch material.materialType {
        case "article": "doc.text.fill"
        case "link": "link"
        case "image": "photo.fill"
        case "video": "video.fill"
        default: "paperclip"
        }
    }

    private func openFile(path: String?) {
        guard let path else { return }
        Task {
            do {
                let url = try await SchoolService.shared.signedPrivateFileURL(path: path)
                await MainActor.run { UIApplication.shared.open(url) }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not open file", error)
                }
            }
        }
    }

    private func openLink(_ value: String) {
        guard let url = URL(string: value) else { return }
        UIApplication.shared.open(url)
    }
}

private struct AssignmentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let surface: AssignmentSurface
    let schoolId: UUID
    let defaultCategory: AssignmentCategory
    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var category: AssignmentCategory
    @State private var dueAt = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @State private var hasDueDate = true
    @State private var materialType = "file"
    @State private var materialURL = ""
    @State private var selectedMaterialFileURL: URL?
    @State private var showingMaterialImporter = false
    @State private var members: [SchoolMember] = []
    @State private var children: [Child] = []
    @State private var selectedRecipientIds = Set<UUID>()
    @State private var selectedChildId: UUID?
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(surface: AssignmentSurface, schoolId: UUID, defaultCategory: AssignmentCategory, onSaved: @escaping () -> Void) {
        self.surface = surface
        self.schoolId = schoolId
        self.defaultCategory = defaultCategory
        self.onSaved = onSaved
        _category = State(initialValue: defaultCategory)
    }

    private var availableCategories: [AssignmentCategory] {
        surface.categories ?? AssignmentCategory.allCases
    }

    private var eligibleMembers: [SchoolMember] {
        let role = appSession.role
        return members.filter { member in
            switch category {
            case .paperwork, .onboarding, .childRecord:
                return member.membership.role == .parent
            case .training, .curriculum:
                if role == .hqDirector {
                    return member.membership.role == .teacher || member.membership.role == .schoolDirector
                }
                return member.membership.role == .teacher
            case .compliance:
                return member.membership.role == .teacher || member.membership.role == .schoolDirector
            case .general:
                return true
            }
        }
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
            && (!selectedRecipientIds.isEmpty || selectedChildId != nil)
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment") {
                    TextField("Title", text: $title)
                    TextField("Instructions", text: $description, axis: .vertical)
                    Picker("Type", selection: $category) {
                        ForEach(availableCategories) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueAt)
                    }
                }

                if children.isEmpty == false && [.paperwork, .childRecord, .onboarding].contains(category) {
                    Section("Child") {
                        Picker("Linked child", selection: $selectedChildId) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(children) { child in
                                Text(child.fullName).tag(Optional(child.id))
                            }
                        }
                    }
                }

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
                    Button(selectedMaterialFileURL?.lastPathComponent ?? "Attach file, picture, or video") {
                        showingMaterialImporter = true
                    }
                }

                Section("Recipients") {
                    Button("Select All Shown") {
                        selectedRecipientIds.formUnion(eligibleMembers.map(\.id))
                    }
                    if selectedMembers.isEmpty == false {
                        ForEach(selectedMembers) { member in
                            HStack {
                                Text("\(member.displayName) · \(member.membership.role.title)")
                                Spacer()
                                Button("Remove") {
                                    selectedRecipientIds.remove(member.id)
                                }
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

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Assignment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Assign") { save() }
                        .disabled(!canSave)
                }
            }
            .task { await loadOptions() }
            .fileImporter(isPresented: $showingMaterialImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                selectedMaterialFileURL = try? result.get().first
            }
            .onChange(of: category) { _, _ in
                selectedRecipientIds = selectedRecipientIds.intersection(Set(eligibleMembers.map(\.id)))
            }
        }
    }

    private func score(_ name: String, query: String) -> Int {
        let lower = name.lowercased()
        if lower.hasPrefix(query) { return 0 }
        if lower.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 1 }
        return 2
    }

    @MainActor
    private func loadOptions() async {
        do {
            async let loadedMembers = SchoolService.shared.fetchMembers(schoolId: schoolId)
            async let loadedChildren = SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)
            members = try await loadedMembers
            children = try await loadedChildren
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load assignment options", error)
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.createAssignment(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    category: category,
                    audienceRole: inferredAudienceRole,
                    childId: selectedChildId,
                    dueAt: hasDueDate ? dueAt : nil,
                    recipientIds: Array(selectedRecipientIds),
                    materialURL: materialURL,
                    materialType: materialType,
                    materialFileURL: selectedMaterialFileURL
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not create assignment", error)
                }
            }
        }
    }

    private var inferredAudienceRole: SchoolRole? {
        switch category {
        case .paperwork, .onboarding, .childRecord:
            return .parent
        case .training, .curriculum:
            return appSession.role == .hqDirector ? nil : .teacher
        case .compliance, .general:
            return nil
        }
    }
}
