import SwiftUI

enum WorkspacePerspective: String, CaseIterable, Identifiable {
    case mine, manage
    var id: String { rawValue }
    var title: String { self == .mine ? "Mine" : "Manage" }
}

enum WorkspaceBucket: String, CaseIterable, Identifiable {
    case attention, waiting, history
    var id: String { rawValue }
    func title(managing: Bool) -> String {
        switch self {
        case .attention: managing ? "Needs review" : "To do"
        case .waiting: "Waiting"
        case .history: "Done"
        }
    }
    static func paperwork(status: String, managing: Bool) -> Self {
        if ["approved", "accepted", "waived", "excused", "rejected", "archived"].contains(status) { return .history }
        if ["submitted", "resubmitted", "pending_review", "in_review", "ambiguous", "error"].contains(status) {
            return managing ? .attention : .waiting
        }
        return managing ? .waiting : .attention
    }
    static func payment(_ status: ZelleInvoiceStatus, managing: Bool) -> Self {
        switch status {
        case .paid, .void, .expired: .history
        case .paymentSubmitted, .underReview: managing ? .attention : .waiting
        default: managing ? .waiting : .attention
        }
    }
}

extension AppSessionManager {
    var workspaceCanManage: Bool {
        activeContext?.membership.accessState == "full"
            && (role == .schoolDirector || role == .hqDirector)
    }
    func workspaceManaging(_ perspective: WorkspacePerspective) -> Bool {
        workspaceCanManage && (role == .hqDirector || perspective == .manage)
    }
}

struct WorkspacePerspectivePicker: View {
    @Binding var selection: WorkspacePerspective
    var attentionCount = 0
    var body: some View {
        Picker("Workspace", selection: $selection) {
            Text(attentionCount > 0 ? "Mine (\(attentionCount))" : "Mine").tag(WorkspacePerspective.mine)
            Text("Manage").tag(WorkspacePerspective.manage)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("workspace-perspective")
    }
}

struct WorkspaceBucketPicker: View {
    @Binding var selection: WorkspaceBucket
    let managing: Bool
    var counts: [WorkspaceBucket: Int] = [:]
    var body: some View {
        Picker("Status", selection: $selection) {
            ForEach(WorkspaceBucket.allCases) { bucket in
                Text("\(bucket.title(managing: managing)) (\(counts[bucket, default: 0]))").tag(bucket)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("workspace-status")
    }
}

/// Stack before decorating: separators never become independently padded cards.
struct WorkspaceList<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(FireflyTheme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius)
                .stroke(FireflyTheme.Colors.separator, lineWidth: 0.5))
    }
}

struct WorkspaceRow: View {
    let title: String
    let subtitle: String
    var trailing: String? = nil
    var symbol = "doc.text"
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(FireflyTheme.Colors.primaryAction)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(FireflyTheme.Typography.rowTitle).foregroundStyle(FireflyTheme.Colors.primaryText)
                Text(subtitle).font(FireflyTheme.Typography.supporting).foregroundStyle(FireflyTheme.Colors.secondaryText)
            }
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(FireflyTheme.Typography.body.weight(.semibold)) }
            Image(systemName: "chevron.right").font(FireflyTheme.Typography.supporting).foregroundStyle(FireflyTheme.Colors.secondaryText)
        }
        .padding(16).frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct WorkspaceGroup<Item>: Identifiable {
    let id: String
    let items: [Item]
}

struct WorkspaceDetailCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if AppConfiguration.workspaceBetaEnabled {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(FireflyTheme.Layout.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FireflyTheme.Colors.card, in: RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius))
        } else { FireflySectionCard { content } }
    }
}
