//
//  AssignmentListComponents.swift
//  FireflyFM
//

import SwiftUI

enum AssignmentArchiveFilter: String, CaseIterable, Identifiable {
    case active
    case archived
    var id: String { rawValue }
    var title: String { self == .active ? "Active" : "Archived" }
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
        case .upcoming: AppConstants.Colors.secondaryText
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

struct AssignmentManagerMetric: Identifiable {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var id: String { title }
}

struct AssignmentManagerMetricCard: View {
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

enum AssignmentCardContext {
    case recipient
    case manager
}

struct AssignmentCardView: View {
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
        if item.lifecycleStatus == .archived {
            indicators.append(.init(title: "Archived", icon: "archivebox.fill", color: .secondary))
        } else if item.lifecycleStatus == .closed {
            indicators.append(.init(title: "Closed", icon: "lock.fill", color: .secondary))
        }
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
            indicators.append(.init(title: item.completionStatus.title, icon: "circle", color: AppConstants.Colors.secondaryText))
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
