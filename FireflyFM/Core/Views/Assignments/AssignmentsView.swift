//
//  AssignmentsView.swift
//  FireflyFM
//

import SwiftUI

enum AssignmentFilter: Hashable {
    case all
    case paperwork
    case learning
    case documents

    var title: String {
        switch self {
        case .all: "Assignments"
        case .paperwork: "Paperwork"
        case .learning: "Training & Curriculum"
        case .documents: "Documents"
        }
    }

    var subtitle: String {
        switch self {
        case .all: "Assignments, submissions, and review status."
        case .paperwork: "Forms, contracts, child paperwork, and parent submissions."
        case .learning: "Training and curriculum assignments with read checks and feedback."
        case .documents: "Onboarding, certificates, licenses, and compliance documents."
        }
    }

    var categories: [AssignmentCategory]? {
        switch self {
        case .all:
            nil
        case .paperwork:
            [.paperwork, .onboarding, .childRecord]
        case .learning:
            [.training, .curriculum]
        case .documents:
            [.onboarding, .compliance]
        }
    }

    var defaultCategory: AssignmentCategory {
        switch self {
        case .paperwork: .paperwork
        case .learning: .training
        case .documents: .onboarding
        case .all: .general
        }
    }
}

enum AssignmentSchoolSelection: Hashable {
    case active
    case selectable
}

struct AssignmentsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    let filter: AssignmentFilter
    let schoolSelection: AssignmentSchoolSelection
    let scopedSchool: School?
    let reviewOnly: Bool

    @State private var model = AssignmentListModel()
    @State private var selectedSchoolId: UUID?
    @State private var showingComposer = false
    @State private var archiveFilter: AssignmentArchiveFilter = .active

    init(
        filter: AssignmentFilter,
        schoolSelection: AssignmentSchoolSelection = .active,
        scopedSchool: School? = nil,
        reviewOnly: Bool = false
    ) {
        self.filter = filter
        self.schoolSelection = schoolSelection
        self.scopedSchool = scopedSchool
        self.reviewOnly = reviewOnly
    }

    private var canCreate: Bool {
        reviewOnly == false && accessPolicy.canCreate
    }

    private var schools: [School] { model.schools }
    private var inboxItems: [AssignmentInboxItem] { model.inboxItems }
    private var reviewItems: [AssignmentInboxItem] { model.reviewItems }

    private var showsManagedWork: Bool {
        reviewOnly || canCreate || reviewItems.isEmpty == false
    }

    private var needsSchoolPicker: Bool {
        scopedSchool == nil && accessPolicy.canSelectSchool && schoolSelection == .selectable
    }

    private var accessPolicy: AssignmentAccessPolicy {
        AssignmentAccessPolicy(context: appSession.accessContext(selectedSchoolId: selectedSchoolId))
    }

    private var title: String {
        guard filter == .all else { return filter.title }
        if accessPolicy.usesFamilyPresentation { return "Paperwork" }
        if accessPolicy.usesSchoolDirectorPresentation { return "Assignments & Training" }
        return filter.title
    }

    private var subtitle: String {
        guard filter == .all else { return filter.subtitle }
        if accessPolicy.usesFamilyPresentation {
            return "Paperwork, forms, and requests from your school."
        }
        if accessPolicy.usesSchoolDirectorPresentation {
            return "Manage school assignments and complete training assigned to you."
        }
        return filter.subtitle
    }

    private var effectiveSchoolId: UUID? {
        scopedSchool?.id ?? (needsSchoolPicker ? selectedSchoolId : appSession.activeSchool?.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        schoolPicker
                        archivePicker

                        if model.phase.isLoading {
                            ProgressView()
                                .tint(AppConstants.Colors.accessibleYellow)
                        } else {
                            if reviewOnly == false {
                                Text(archiveFilter == .active ? "My Work" : "My Archived Work")
                                    .font(.title2.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                if inboxItems.isEmpty {
                                    emptyPanel(archiveFilter == .active ? "No assigned work yet." : "No archived assignments.")
                                } else {
                                    ForEach(AssignmentAgendaSection.allCases) { section in
                                        let items = agendaItems(in: section)
                                        if items.isEmpty == false {
                                            agendaSection(section, items: items)
                                        }
                                    }
                                }
                            }

                            if showsManagedWork {
                                if archiveFilter == .active { managerSummary }
                                managerQueue
                            }
                        }

                        if let errorMessage = model.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(reviewOnly ? "Review Submissions" : title)
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
                        filter: filter,
                        schoolId: schoolId,
                        defaultCategory: filter.defaultCategory
                    ) {
                        Task { await loadAssignments() }
                    }
                }
            }
            .task(id: appSession.activeMembershipId) { await loadInitialData() }
            .refreshable { await loadAssignments() }
        }
    }

    private var archivePicker: some View {
        Picker("Assignment View", selection: $archiveFilter) {
            ForEach(AssignmentArchiveFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: archiveFilter) { _, _ in Task { await loadAssignments() } }
        .accessibilityIdentifier("assignment-archive-filter")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let scopedSchool {
                Text(scopedSchool.name)
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
            Text(reviewOnly
                 ? "Review submitted onboarding work and send feedback before access is approved."
                 : subtitle)
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
            Text(reviewOnly ? "Submission Status" : "Assignments I Manage")
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
            Text(reviewOnly
                 ? (archiveFilter == .active ? "Submitted Work" : "Archived Submitted Work")
                 : (archiveFilter == .active ? "Assignment Progress" : "Archived Assignments I Manage"))
                .font(.title2.bold())
                .foregroundColor(AppConstants.Colors.primaryText)

            if reviewItems.isEmpty {
                emptyPanel(reviewOnly
                           ? "No onboarding submissions are ready for review."
                           : (archiveFilter == .active ? "No assignments to manage yet." : "No archived assignments to manage."))
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
            AssignmentManagerMetric(title: "Not Started", count: notStarted, icon: "circle.dotted", color: AppConstants.Colors.secondaryText),
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
        if needsSchoolPicker {
            await model.loadSchools()
            if selectedSchoolId == nil {
                selectedSchoolId = model.schools.first?.id
            }
        }
        await loadAssignments()
    }

    @MainActor
    private func loadAssignments() async {
        await model.load(
            schoolId: effectiveSchoolId,
            categories: filter.categories,
            archived: archiveFilter == .archived,
            reviewOnly: reviewOnly
        )
    }
}
