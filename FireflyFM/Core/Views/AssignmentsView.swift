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
    @State private var showingComposer = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canCreate: Bool {
        appSession.role?.canManageSchool == true
    }

    private var showsManagedWork: Bool {
        canCreate || reviewItems.isEmpty == false
    }

    private var needsSchoolPicker: Bool {
        appSession.role == .hqDirector && surface == .hqEducation
    }

    private var effectiveSchoolId: UUID? {
        needsSchoolPicker ? selectedSchoolId : appSession.activeSchool?.id
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        schoolPicker

                        if isLoading {
                            ProgressView()
                                .tint(AppConstants.Colors.accessibleYellow)
                        } else {
                            Text("My Work")
                                .font(.title2.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            if inboxItems.isEmpty {
                                emptyPanel("No assigned work yet.")
                            } else {
                                ForEach(AssignmentAgendaSection.allCases) { section in
                                    let items = agendaItems(in: section)
                                    if items.isEmpty == false {
                                        agendaSection(section, items: items)
                                    }
                                }
                            }

                            if showsManagedWork {
                                managerSummary
                                managerQueue
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
            .task(id: appSession.activeMembershipId) { await loadInitialData() }
            .refreshable { await loadAssignments() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(surface.title)
                .font(.largeTitle.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(surface.subtitle)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
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

    private var managerSummary: some View {
        return VStack(alignment: .leading, spacing: 10) {
            Text("Assignments I Manage")
                .font(.title2.bold())
                .foregroundColor(AppConstants.Colors.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(managerMetrics) { metric in
                        AssignmentManagerMetricCard(metric: metric)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var managerQueue: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assignment Progress")
                .font(.title2.bold())
                .foregroundColor(AppConstants.Colors.primaryText)

            if reviewItems.isEmpty {
                emptyPanel("No published assignments to manage yet.")
            } else {
                ForEach(reviewItems) { item in
                    assignmentLink(item, context: .manager)
                }
            }
        }
    }

    private func agendaSection(_ section: AssignmentAgendaSection, items: [AssignmentInboxItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(section.title, systemImage: section.icon)
                    .font(.headline)
                    .foregroundColor(section.color)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.52))
            }

            ForEach(items) { item in
                assignmentLink(item, context: .recipient)
            }
        }
    }

    private func assignmentLink(_ item: AssignmentInboxItem, context: AssignmentCardContext) -> some View {
        NavigationLink {
            AssignmentDetailView(assignmentId: item.assignmentId) {
                Task { await loadAssignments() }
            }
        } label: {
            AssignmentCardView(item: item, context: context)
        }
        .buttonStyle(.plain)
    }

    private func agendaItems(in section: AssignmentAgendaSection) -> [AssignmentInboxItem] {
        inboxItems
            .filter { agendaSection(for: $0) == section }
            .sorted { lhs, rhs in
                switch (lhs.dueAt, rhs.dueAt) {
                case let (left?, right?): left < right
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
                }
            }
    }

    private func agendaSection(for item: AssignmentInboxItem) -> AssignmentAgendaSection {
        AssignmentAgendaSection.classify(item)
    }

    private var managerMetrics: [AssignmentManagerMetric] {
        let now = Date()
        let needsReview = reviewItems.reduce(0) {
            $0 + ($1.needsReviewCount ?? ($1.reviewStatus == "submitted" ? $1.submissionCount : 0))
        }
        let changesRequested = reviewItems.reduce(0) {
            $0 + ($1.changesRequestedCount ?? (["changes_requested", "flagged"].contains($1.reviewStatus ?? "") ? 1 : 0))
        }
        let notStarted = reviewItems.reduce(0) {
            $0 + ($1.notStartedCount ?? max(0, $1.recipientCount - $1.submissionCount))
        }
        let overdue = reviewItems.reduce(0) { count, item in
            if let overdueCount = item.overdueCount { return count + overdueCount }
            guard item.dueAt.map({ $0 < now }) == true else { return count }
            return count + max(0, item.recipientCount - item.submissionCount)
        }
        let complete = reviewItems.reduce(0) {
            $0 + ($1.completeCount ?? ($1.completionStatus == .accepted ? $1.recipientCount : 0))
        }

        return [
            AssignmentManagerMetric(title: "Needs Review", count: needsReview, icon: "doc.text.magnifyingglass", color: .orange),
            AssignmentManagerMetric(title: "Changes Requested", count: changesRequested, icon: "arrow.uturn.backward.circle.fill", color: .red),
            AssignmentManagerMetric(title: "Not Started", count: notStarted, icon: "circle.dotted", color: .white.opacity(0.68)),
            AssignmentManagerMetric(title: "Overdue", count: overdue, icon: "exclamationmark.triangle.fill", color: .red),
            AssignmentManagerMetric(title: "Complete", count: complete, icon: "checkmark.circle.fill", color: .green)
        ]
    }

    private func emptyPanel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
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
            async let loadedInbox = SchoolWorkflowService.shared.fetchAssignmentInbox(categories: surface.categories)
            async let loadedReview = SchoolWorkflowService.shared.fetchAssignmentReviewQueue(
                schoolId: schoolId,
                categories: surface.categories
            )
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

enum AssignmentAgendaSection: String, CaseIterable, Identifiable {
    case needsAttention
    case today
    case upcoming
    case awaitingReview
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsAttention: "Needs Attention"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .awaitingReview: "Awaiting Review"
        case .completed: "Completed"
        }
    }

    var icon: String {
        switch self {
        case .needsAttention: "exclamationmark.circle.fill"
        case .today: "sun.max.fill"
        case .upcoming: "calendar"
        case .awaitingReview: "hourglass"
        case .completed: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .needsAttention: .red
        case .today: AppConstants.Colors.accessibleYellow
        case .upcoming: .white.opacity(0.72)
        case .awaitingReview: .orange
        case .completed: .green
        }
    }

    static func classify(
        _ item: AssignmentInboxItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AssignmentAgendaSection {
        if item.hasUnreadFeedback == true
            || [.changesRequested, .flagged, .overdue].contains(item.completionStatus)
            || item.reviewStatus == "changes_requested"
            || item.reviewStatus == "flagged" {
            return .needsAttention
        }

        if [.submitted, .resubmitted].contains(item.completionStatus) {
            return .awaitingReview
        }

        if [.reviewed, .accepted, .excused].contains(item.completionStatus) {
            return .completed
        }

        if let dueAt = item.dueAt {
            if dueAt < now { return .needsAttention }
            if calendar.isDate(dueAt, inSameDayAs: now) { return .today }
        }
        return .upcoming
    }
}

private struct AssignmentManagerMetric: Identifiable {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var id: String { title }
}

private struct AssignmentManagerMetricCard: View {
    let metric: AssignmentManagerMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: metric.icon)
                .foregroundColor(metric.color)
            Text("\(metric.count)")
                .font(.title2.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
                .minimumScaleFactor(0.75)
            Text(metric.title)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(height: 32, alignment: .topLeading)
        }
        .padding()
        .frame(width: 144, height: 126, alignment: .topLeading)
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assignment-manager-metric-\(metric.id)")
    }
}

private enum AssignmentCardContext {
    case recipient
    case manager
}

private struct AssignmentCardView: View {
    let item: AssignmentInboxItem
    let context: AssignmentCardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.primaryText)
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.35))
            }

            HStack(spacing: 8) {
                Label(item.category.title, systemImage: icon)
                if let schoolName = item.schoolName, schoolName.isEmpty == false {
                    Label(schoolName, systemImage: "building.2")
                }
                if let dueAt = item.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                }
                if let childName = item.childDisplayName {
                    Label(childName, systemImage: "figure.child")
                }
            }
            .font(.caption)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(statusIndicators) { indicator in
                        statusBadge(indicator)
                    }
                }
            }

            if context == .manager {
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

    private func statusBadge(_ indicator: AssignmentStatusIndicator) -> some View {
        Label(indicator.title, systemImage: indicator.icon)
            .font(.caption.bold())
            .foregroundColor(indicator.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(indicator.color.opacity(0.12))
            .cornerRadius(8)
    }

    private var statusIndicators: [AssignmentStatusIndicator] {
        var indicators: [AssignmentStatusIndicator] = []
        let isOverdue = item.dueAt.map { $0 < Date() } == true
            && [.notStarted, .read, .changesRequested, .overdue, .flagged].contains(item.completionStatus)

        if context == .recipient && item.viewedAt == nil {
            indicators.append(.init(title: "Unread", icon: "circle.fill", color: AppConstants.Colors.accessibleYellow))
        }
        if isOverdue || item.completionStatus == .overdue {
            indicators.append(.init(title: "Overdue", icon: "exclamationmark.triangle.fill", color: .red))
        }
        if item.completionStatus == .submitted || item.completionStatus == .resubmitted {
            indicators.append(.init(
                title: item.completionStatus == .resubmitted ? "Resubmitted" : "Submitted",
                icon: "paperplane.fill",
                color: .orange
            ))
        }
        if item.hasUnreadFeedback == true || item.reviewerMessage?.isEmpty == false || item.completionStatus == .reviewed {
            indicators.append(.init(title: "Feedback", icon: "text.bubble.fill", color: .cyan))
        }
        if item.completionStatus == .changesRequested
            || item.completionStatus == .flagged
            || item.reviewStatus == "changes_requested"
            || item.reviewStatus == "flagged" {
            indicators.append(.init(title: "Redo Required", icon: "arrow.uturn.backward.circle.fill", color: .red))
        }
        if item.completionStatus == .accepted {
            indicators.append(.init(title: "Accepted", icon: "checkmark.circle.fill", color: .green))
        }
        if item.completionStatus == .excused {
            indicators.append(.init(title: "Excused", icon: "minus.circle.fill", color: .cyan))
        }
        if indicators.isEmpty {
            indicators.append(.init(title: item.completionStatus.title, icon: "circle", color: .white.opacity(0.68)))
        }
        return indicators
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

private struct AssignmentStatusIndicator: Identifiable {
    let title: String
    let icon: String
    let color: Color

    var id: String { title }
}

struct AssignmentDetailView: View {
    let assignmentId: UUID
    var onChanged: () -> Void = {}

    @State private var bundle: AssignmentDetailBundle?
    @State private var profilesById: [UUID: UserProfile] = [:]
    @State private var currentUserId: UUID?
    @State private var feedbackText = ""
    @State private var selectedFileURLs: [URL] = []
    @State private var showingImporter = false
    @State private var selectedReviewUserId: UUID?
    @State private var reviewMessage = ""
    @State private var waiverReason = ""
    @State private var showingWaiverConfirmation = false
    @State private var commentDrafts: [UUID: String] = [:]
    @State private var submissionMutationKey = UUID().uuidString
    @State private var reviewMutationKeys: [String: String] = [:]
    @State private var commentMutationKeys: [UUID: String] = [:]
    @State private var hasMarkedViewed = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var assignment: Assignment? { bundle?.assignment }

    private var mySubmission: AssignmentSubmission? {
        guard let currentUserId else { return nil }
        return bundle?.submissions.first { $0.submittedBy == currentUserId }
    }

    private var mySubmissions: [AssignmentSubmission] {
        guard let currentUserId else { return [] }
        return bundle?.submissions.filter { $0.submittedBy == currentUserId } ?? []
    }

    private var isRead: Bool {
        guard let currentUserId else { return false }
        return bundle?.readReceipts.contains { $0.userId == currentUserId } == true
    }

    private var canSubmit: Bool {
        bundle?.capabilities.canSubmit == true
    }

    private var canReview: Bool {
        bundle?.capabilities.canReview == true
    }

    private var canManageAssignment: Bool {
        bundle?.capabilities.canManage == true
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
                        if bundle.capabilities.canAcknowledge {
                            readSection
                        }
                        if bundle.capabilities.isRecipient {
                            submitSection(bundle.assignment)
                            feedbackSection(
                                bundle,
                                recipientId: bundle.capabilities.userId,
                                submission: mySubmission,
                                title: "My Comments"
                            )
                            recipientActivitySection(recipientEvents(in: bundle))
                        }
                        if canReview {
                            reviewSection(bundle)
                            managementHistorySection(bundle.events)
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
        .navigationTitle("Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManageAssignment, let assignment {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if assignment.status == "draft" || assignment.status == "scheduled" {
                            Button {
                                changeStatus(to: "published")
                            } label: {
                                Label("Publish Now", systemImage: "paperplane.fill")
                            }
                        }
                        if assignment.status == "published" || assignment.status == "scheduled" {
                            Button {
                                changeStatus(to: "closed")
                            } label: {
                                Label("Close", systemImage: "lock.fill")
                            }
                        }
                        Button(role: .destructive) {
                            changeStatus(to: "archived")
                        } label: {
                            Label("Archive", systemImage: "archivebox.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if let urls = try? result.get() {
                selectedFileURLs.append(contentsOf: urls.filter { selectedFileURLs.contains($0) == false })
            }
        }
        .confirmationDialog(
            "Waive this onboarding requirement?",
            isPresented: $showingWaiverConfirmation,
            titleVisibility: .visible
        ) {
            Button("Waive Requirement", role: .destructive) { waiveOnboardingRequirement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recorded reason will remain in the audit history, and this requirement will no longer block access.")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(assignment.category.title)
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppConstants.Colors.accessibleYellow)
                    .cornerRadius(8)
                if let status = assignment.status {
                    Text(submissionStatusTitle(status))
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.1))
                        .cornerRadius(8)
                }
                Spacer()
                if let dueAt = assignment.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                }
            }
            Text(assignment.title)
                .font(.largeTitle.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            if let description = assignment.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
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
                            .foregroundColor(AppConstants.Colors.primaryText)
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
        .accessibilityIdentifier("assignment-recipient-acknowledgment")
    }

    private func submitSection(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Submission")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            if let mySubmission {
                Text("Latest attempt: \(submissionStatusTitle(mySubmission.status)) · \(mySubmission.submittedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Submitted")")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                if let message = mySubmission.reviewerMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                        .padding(8)
                        .background(AppConstants.Colors.background.opacity(0.45))
                        .cornerRadius(8)
                }
            }

            if canSubmit {
                TextEditor(text: $feedbackText)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .padding(8)
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)

                Button(selectedFileURLs.isEmpty ? "Attach files, photos, or videos" : "Add More Attachments") {
                    showingImporter = true
                }
                .buttonStyle(.bordered)
                .tint(AppConstants.Colors.accessibleYellow)

                ForEach(selectedFileURLs, id: \.self) { url in
                    HStack {
                        Label(url.lastPathComponent, systemImage: "paperclip")
                            .lineLimit(1)
                        Spacer()
                        Button("Remove") { selectedFileURLs.removeAll { $0 == url } }
                    }
                    .font(.caption)
                }

                Button(mySubmission == nil ? "Submit Assignment" : "Submit Revised Attempt") {
                    submit(assignment)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppConstants.Colors.accessibleYellow)
                .disabled(isSaving || (selectedFileURLs.isEmpty && feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            } else if mySubmission == nil {
                smallPanel("This assignment is not currently open for submission.")
            }

            if mySubmissions.isEmpty == false {
                Divider().overlay(.white.opacity(0.12))
                Text("Attempt History")
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                attemptHistory(mySubmissions, bundle: bundle)
            }
        }
        .padding()
        .background(AppConstants.Colors.card.opacity(0.72))
        .cornerRadius(8)
        .accessibilityIdentifier("assignment-recipient-panel")
    }

    private func reviewSection(_ bundle: AssignmentDetailBundle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            let userIds = reviewUserIds(bundle)
            if userIds.isEmpty {
                smallPanel("No other recipients are available to review.")
            } else {
                reviewRecipientSelector(userIds)

                if bundle.assignment.category == .onboarding,
                   bundle.recipients.contains(where: { [.accepted, .excused].contains($0.completionStatus) }) == false {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Waiver reason (required)", text: $waiverReason, axis: .vertical)
                            .padding(12)
                            .background(AppConstants.Colors.card)
                            .cornerRadius(8)
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Button {
                            showingWaiverConfirmation = true
                        } label: {
                            Label("Waive Requirement", systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(isSaving || waiverReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Use a waiver only when the requirement is not needed. A reason is required and remains visible in the audit history.")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                    }
                }

                if let userId = selectedReviewUserId ?? userIds.first {
                    let attempts = bundle.submissions.filter { $0.submittedBy == userId }
                    if let latest = attempts.first {
                        submissionPreview(latest, bundle: bundle)

                        if ["submitted", "resubmitted"].contains(latest.status) {
                            TextField("Decision feedback", text: $reviewMessage, axis: .vertical)
                                .padding(12)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(8)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)

                            HStack {
                                Button {
                                    review(latest, status: "changes_requested")
                                } label: {
                                    Label("Request Changes", systemImage: "arrow.uturn.backward")
                                }
                                .disabled(isSaving || reviewMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("assignment-request-changes")
                                Button {
                                    review(latest, status: "accepted")
                                } label: {
                                    Label("Accept", systemImage: "checkmark")
                                }
                                .disabled(isSaving)
                                .accessibilityIdentifier("assignment-accept")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppConstants.Colors.accessibleYellow)
                        } else {
                            smallPanel("This attempt has already been reviewed. A new attempt appears only after changes are requested.")
                        }

                        Text("Attempt History")
                            .font(.subheadline.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        attemptHistory(attempts, bundle: bundle)
                        feedbackSection(
                            bundle,
                            recipientId: userId,
                            submission: latest,
                            title: "Comments with Recipient"
                        )
                    } else {
                        smallPanel("This recipient has not started yet.")
                    }
                }
            }
        }
        .accessibilityIdentifier("assignment-creator-panel")
    }

    private func reviewRecipientSelector(_ userIds: [UUID]) -> some View {
        HStack(spacing: 10) {
            Button {
                moveReviewRecipient(by: -1, userIds: userIds)
            } label: {
                Image(systemName: "chevron.left")
            }

            Menu {
                ForEach(userIds, id: \.self) { userId in
                    Button(profilesById[userId]?.displayName ?? "School member") {
                        selectedReviewUserId = userId
                        reviewMessage = ""
                    }
                }
            } label: {
                HStack {
                    Text(profilesById[selectedReviewUserId ?? userIds[0]]?.displayName ?? "School member")
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 42)
            }

            Button {
                moveReviewRecipient(by: 1, userIds: userIds)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.bordered)
        .tint(AppConstants.Colors.accessibleYellow)
    }

    private func submissionPreview(_ submission: AssignmentSubmission, bundle: AssignmentDetailBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Submission Preview", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text(submissionStatusTitle(submission.status))
                    .font(.caption.bold())
                    .foregroundColor(.orange)
            }

            let attachments = bundle.attachments.filter { $0.submissionId == submission.id }
            if attachments.isEmpty {
                Text("Text response only")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
            } else {
                ForEach(attachments) { attachment in
                    Button {
                        openFile(path: attachment.privateFilePath)
                    } label: {
                        Label(attachment.fileName ?? "Attachment", systemImage: "paperclip")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppConstants.Colors.accessibleYellow)
                }
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func attemptHistory(_ submissions: [AssignmentSubmission], bundle: AssignmentDetailBundle?) -> some View {
        VStack(spacing: 8) {
            ForEach(submissions) { submission in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Attempt \(submission.attemptNumber ?? fallbackAttemptNumber(submission, in: submissions))")
                            .font(.subheadline.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Spacer()
                        Text(submissionStatusTitle(submission.status))
                            .font(.caption.bold())
                            .foregroundColor(submission.status == "accepted" ? .green : .orange)
                    }
                    if let submittedAt = submission.submittedAt {
                        Text(submittedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.52))
                    }
                    if let message = submission.reviewerMessage, message.isEmpty == false {
                        Label(message, systemImage: "text.bubble.fill")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                    }
                    if let bundle {
                        ForEach(bundle.attachments.filter { $0.submissionId == submission.id }) { attachment in
                            Button {
                                openFile(path: attachment.privateFilePath)
                            } label: {
                                Label(attachment.fileName ?? "Attachment", systemImage: "paperclip")
                            }
                            .buttonStyle(.bordered)
                            .tint(AppConstants.Colors.accessibleYellow)
                        }
                        if submission.id != submissions.first?.id {
                            let historicalComments = bundle.feedbackMessages.filter {
                                $0.submissionId == submission.id
                            }
                            if historicalComments.isEmpty == false {
                                Label("Comments", systemImage: "text.bubble")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                                ForEach(historicalComments) { comment in
                                    Text(comment.body)
                                        .font(.caption)
                                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(AppConstants.Colors.background.opacity(0.45))
                .cornerRadius(8)
            }
        }
    }

    private func feedbackSection(
        _ bundle: AssignmentDetailBundle,
        recipientId: UUID,
        submission: AssignmentSubmission?,
        title: String
    ) -> some View {
        let messages = bundle.feedbackMessages.filter { message in
            message.recipientId == recipientId && message.submissionId == submission?.id
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            if messages.isEmpty {
                smallPanel("No comments on this attempt yet.")
            } else {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profilesById[message.senderId]?.displayName ?? "School member")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                        Text(message.body)
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.primaryText)
                    }
                    .padding()
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                }
            }

            if let submission {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Add a comment", text: commentBinding(for: submission.id), axis: .vertical)
                        .padding(10)
                        .background(AppConstants.Colors.card)
                        .cornerRadius(8)
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Button {
                        postComment(on: submission)
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppConstants.Colors.accessibleYellow)
                    .disabled(isSaving || commentDraft(for: submission.id).isEmpty)
                    .accessibilityLabel("Send comment")
                }
            }
        }
    }

    private func recipientActivitySection(_ events: [AssignmentEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Activity")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            if events.isEmpty {
                smallPanel("No workflow events recorded yet.")
            } else {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: eventIcon(event.eventType))
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(submissionStatusTitle(event.eventType))
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            HStack(spacing: 4) {
                                if let actorId = event.actorId {
                                    Text(profilesById[actorId]?.displayName ?? "School member")
                                }
                                if let createdAt = event.createdAt {
                                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.52))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                }
            }
        }
    }

    private func recipientEvents(in bundle: AssignmentDetailBundle) -> [AssignmentEvent] {
        let userId = bundle.capabilities.userId
        let ownSubmissionIds = Set(
            bundle.submissions
                .filter { $0.submittedBy == userId }
                .map(\.id)
        )
        let lifecycleEvents: Set<String> = ["draft", "scheduled", "published", "closed", "archived"]
        return bundle.events.filter { event in
            lifecycleEvents.contains(event.eventType) == false
                && (
                    event.actorId == userId
                    || event.metadata?.recipientId == userId
                    || event.metadata?.submissionId.map(ownSubmissionIds.contains) == true
                )
        }
    }

    @ViewBuilder
    private func managementHistorySection(_ events: [AssignmentEvent]) -> some View {
        let lifecycleEvents = events.filter {
            ["draft", "scheduled", "published", "closed", "archived"].contains($0.eventType)
        }
        if lifecycleEvents.isEmpty == false {
            DisclosureGroup {
                VStack(spacing: 8) {
                    ForEach(lifecycleEvents) { event in
                        HStack {
                            Label(submissionStatusTitle(event.eventType), systemImage: eventIcon(event.eventType))
                            Spacer()
                            if let createdAt = event.createdAt {
                                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Assignment History")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
            .tint(AppConstants.Colors.accessibleYellow)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
        }
    }

    private func eventIcon(_ eventType: String) -> String {
        switch eventType {
        case "accepted": "checkmark.circle.fill"
        case "changes_requested": "arrow.uturn.backward.circle.fill"
        case "submitted", "resubmitted": "paperplane.fill"
        case "published": "megaphone.fill"
        case "closed": "lock.fill"
        case "archived": "archivebox.fill"
        default: "clock.arrow.circlepath"
        }
    }

    private func smallPanel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
    }

    private func reviewUserIds(_ bundle: AssignmentDetailBundle) -> [UUID] {
        let recipientIds = bundle.recipients.map(\.userId)
        let submissionIds = bundle.submissions.map(\.submittedBy)
        return Array(Set(recipientIds + submissionIds))
            .filter { $0 != bundle.capabilities.userId }
            .sorted { lhs, rhs in
            let left = profilesById[lhs]?.displayName ?? ""
            let right = profilesById[rhs]?.displayName ?? ""
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    private func moveReviewRecipient(by offset: Int, userIds: [UUID]) {
        guard userIds.isEmpty == false else { return }
        let current = selectedReviewUserId ?? userIds[0]
        let currentIndex = userIds.firstIndex(of: current) ?? 0
        let nextIndex = (currentIndex + offset + userIds.count) % userIds.count
        selectedReviewUserId = userIds[nextIndex]
        reviewMessage = ""
    }

    private func fallbackAttemptNumber(_ submission: AssignmentSubmission, in submissions: [AssignmentSubmission]) -> Int {
        guard let index = submissions.firstIndex(where: { $0.id == submission.id }) else { return 1 }
        return submissions.count - index
    }

    private func submissionStatusTitle(_ status: String) -> String {
        status
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            var loaded = try await SchoolWorkflowService.shared.fetchAssignmentDetail(assignmentId: assignmentId)
            currentUserId = loaded.capabilities.userId
            if loaded.capabilities.isRecipient, hasMarkedViewed == false {
                hasMarkedViewed = true
                do {
                    try await SchoolWorkflowService.shared.markAssignmentViewed(assignmentId: assignmentId)
                    onChanged()
                    loaded = try await SchoolWorkflowService.shared.fetchAssignmentDetail(assignmentId: assignmentId)
                } catch where AppErrorMessage.isCancellation(error) {
                    isLoading = false
                    return
                } catch {
                    errorMessage = AppErrorMessage.school("Assignment opened, but its unread state could not be cleared", error)
                }
            }
            bundle = loaded
            let profileIds = Set(
                loaded.recipients.map(\.userId)
                    + loaded.submissions.map(\.submittedBy)
                    + loaded.feedbackMessages.map(\.senderId)
                    + loaded.events.compactMap(\.actorId)
            )
            profilesById = try await ProfileService.shared.fetchProfiles(ids: Array(profileIds))
            let availableReviewIds = reviewUserIds(loaded)
            if selectedReviewUserId.map(availableReviewIds.contains) != true {
                selectedReviewUserId = availableReviewIds.first
            }
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load assignment", error)
            isLoading = false
        }
    }

    private func markRead() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.acknowledgeAssignment(assignmentId: assignmentId)
                await MainActor.run { isSaving = false }
                await load()
                onChanged()
            } catch {
                await MainActor.run {
                    isSaving = false
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
                    fileURLs: selectedFileURLs,
                    feedbackText: feedbackText,
                    idempotencyKey: submissionMutationKey
                )
                await MainActor.run {
                    selectedFileURLs = []
                    feedbackText = ""
                    submissionMutationKey = UUID().uuidString
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
        let mutationKeyId = "\(submission.id.uuidString):\(status)"
        let mutationKey = reviewMutationKeys[mutationKeyId] ?? UUID().uuidString
        reviewMutationKeys[mutationKeyId] = mutationKey
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.reviewAssignmentSubmission(
                    submissionId: submission.id,
                    status: status,
                    message: reviewMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reviewMessage,
                    idempotencyKey: mutationKey
                )
                await MainActor.run {
                    reviewMessage = ""
                    reviewMutationKeys[mutationKeyId] = nil
                    isSaving = false
                }
                await load()
                onChanged()
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not review assignment", error)
                }
            }
        }
    }

    private func waiveOnboardingRequirement() {
        guard let assignment, assignment.category == .onboarding else { return }
        let reason = waiverReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.isEmpty == false else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.waiveOnboardingAssignment(
                    assignmentId: assignment.id,
                    reason: reason
                )
                await MainActor.run {
                    waiverReason = ""
                    isSaving = false
                }
                await load()
                onChanged()
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not waive requirement", error)
                }
            }
        }
    }

    private func postComment(on submission: AssignmentSubmission) {
        let body = commentDraft(for: submission.id)
        guard body.isEmpty == false else { return }
        let mutationKey = commentMutationKeys[submission.id] ?? UUID().uuidString
        commentMutationKeys[submission.id] = mutationKey
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.postAssignmentComment(
                    submissionId: submission.id,
                    body: body,
                    idempotencyKey: mutationKey
                )
                await MainActor.run {
                    commentDrafts[submission.id] = ""
                    commentMutationKeys[submission.id] = nil
                    isSaving = false
                }
                await load()
                onChanged()
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not send comment", error)
                }
            }
        }
    }

    private func commentDraft(for submissionId: UUID) -> String {
        (commentDrafts[submissionId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commentBinding(for submissionId: UUID) -> Binding<String> {
        Binding(
            get: { commentDrafts[submissionId] ?? "" },
            set: { commentDrafts[submissionId] = $0 }
        )
    }

    private func changeStatus(to status: String) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.setAssignmentStatus(
                    assignmentId: assignmentId,
                    status: status
                )
                await MainActor.run { isSaving = false }
                await load()
                onChanged()
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not update assignment status", error)
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
    @State private var selectedMaterialFileURLs: [URL] = []
    @State private var showingMaterialImporter = false
    @State private var members: [SchoolMember] = []
    @State private var children: [Child] = []
    @State private var selectedRecipientIds = Set<UUID>()
    @State private var selectedChildId: UUID?
    @State private var searchText = ""
    @State private var mutationKey = UUID().uuidString
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
            && (!resolvedRecipientIds.isEmpty || selectedChildId != nil)
            && !isSaving
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
            errorMessage = "Material links must be complete http:// or https:// URLs."
            return
        }
        materialURLs.append(value)
        materialURL = ""
        errorMessage = nil
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
            selectedAudienceRole = eligibleRoles.first ?? .teacher
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
                    childId: audienceMode == .child ? selectedChildId : nil,
                    dueAt: hasDueDate ? dueAt : nil,
                    recipientIds: resolvedRecipientIds,
                    materialURLs: materialURLs,
                    materialType: materialType,
                    materialFileURLs: selectedMaterialFileURLs,
                    status: publication.status,
                    publishAt: publication == .scheduled ? publishAt : nil,
                    idempotencyKey: mutationKey
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
        if audienceMode == .role { return selectedAudienceRole }
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
