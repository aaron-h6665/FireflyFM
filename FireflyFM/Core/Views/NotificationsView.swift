//
//  NotificationsView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var notificationInbox: NotificationInboxStore

    @State private var notifications: [NotificationInboxItem] = []
    @State private var members: [SchoolMember] = []
    @State private var showingComposer = false
    @State private var showingClearConfirmation = false
    @State private var isClearing = false
    @State private var deletingNotificationIDs = Set<UUID>()
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canCompose: Bool {
        appSession.role == .parent || appSession.role == .teacher || appSession.role?.canManageSchool == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 12)

                    List {
                        Text(descriptionText)
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.65))
                            .notificationListRow()

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .notificationListRow()
                        }

                        if isLoading {
                            ProgressView()
                                .tint(AppConstants.Colors.primaryAction)
                                .frame(maxWidth: .infinity)
                                .notificationListRow()
                        } else if notifications.isEmpty {
                            emptyPanel("No notifications yet.")
                                .notificationListRow()
                        } else {
                            ForEach(notifications) { notification in
                                NavigationLink {
                                    notificationDestination(notification)
                                        .task { await markRead(notification) }
                                } label: {
                                    notificationCard(notification)
                                }
                                .buttonStyle(.plain)
                                .notificationListRow()
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(notification)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(isClearing || deletingNotificationIDs.contains(notification.id))
                                }
                            }
                        }

                        Color.clear
                            .frame(height: 8)
                            .notificationListRow()
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingComposer) {
                SchoolNotificationComposerView(members: members) {
                    Task { await load() }
                }
            }
            .alert("Clear all notifications?", isPresented: $showingClearConfirmation) {
                Button("Clear All", role: .destructive) {
                    Task { await dismissAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every notification from your inbox. It does not remove notifications from anyone else's inbox.")
            }
            .task(id: appSession.activeMembershipId) { await load() }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Notifications")
                    .font(.largeTitle.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)

                Spacer(minLength: 8)

                if canCompose {
                    Button {
                        showingComposer = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(AppConstants.Colors.primaryAction)
                            .frame(
                                width: AppConstants.Layout.minimumTapTarget,
                                height: AppConstants.Layout.minimumTapTarget
                            )
                            .background(AppConstants.Colors.card)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New notification")
                }
            }

            HStack {
                Text(notificationSummary)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.secondaryText)

                Spacer()

                if isClearing || notifications.isEmpty == false {
                    Button {
                        showingClearConfirmation = true
                    } label: {
                        HStack(spacing: 7) {
                            if isClearing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text(isClearing ? "Clearing" : "Clear all")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                        .frame(minHeight: AppConstants.Layout.minimumTapTarget)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isClearing || deletingNotificationIDs.isEmpty == false)
                    .accessibilityLabel(isClearing ? "Clearing notifications" : "Clear all notifications")
                }
            }
        }
    }

    private var notificationSummary: String {
        if isClearing {
            return "Removing notifications…"
        }
        switch notifications.count {
        case 0:
            return "You’re all caught up"
        case 1:
            return "1 notification"
        default:
            return "\(notifications.count) notifications"
        }
    }

    private var descriptionText: String {
        switch appSession.role {
        case .parent:
            "Send medicine, pickup, absence, and birthday notes; receive paperwork, child updates, receipts, events, newsletters, and school announcements."
        case .teacher:
            "Training, curriculum updates, director announcements, events, and child workflow reminders."
        case .schoolDirector, .hqDirector:
            "Your cross-school assignment inbox, submission feedback, and school alerts."
        case .none:
            "School notifications."
        }
    }

    private func notificationCard(_ notification: NotificationInboxItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if notification.readAt == nil {
                    Circle()
                        .fill(AppConstants.Colors.accessibleYellow)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Unread")
                }
                Text(notification.title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            Text(notification.body)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Text(notification.category.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption2.bold())
                .foregroundColor(AppConstants.Colors.brandNavy)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppConstants.Colors.accessibleYellow)
                .clipShape(Capsule())
            Label(notification.schoolName, systemImage: "building.2")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
            if let createdAt = notification.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
            }
        }
        .padding(16)
        .background(AppConstants.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func notificationDestination(_ notification: NotificationInboxItem) -> some View {
        switch notification.sourceType {
        case "assignment":
            if let assignmentId = notification.sourceId {
                AssignmentDetailView(assignmentId: assignmentId) {
                    Task { await load() }
                }
            } else {
                NotificationDetailView(notification: notification)
            }
        case "paperwork_assignment":
            PaperworkView()
        case "school_event":
            EventsView()
        case "training_assignment":
            CurriculumView()
        case "medication_instruction":
            ChildrenView()
        default:
            switch notification.category {
            case "paperwork_due", "paperwork_reviewed":
                PaperworkView()
            case "event_change":
                EventsView()
            case "training_assigned", "training_reviewed", "curriculum_update":
                CurriculumView()
            case "assignment_assigned", "assignment_submitted", "assignment_reviewed", "assignment_feedback":
                if let assignmentId = notification.sourceId {
                    AssignmentDetailView(assignmentId: assignmentId) {
                        Task { await load() }
                    }
                } else {
                    NotificationDetailView(notification: notification)
                }
            case "child_update", "medicine_instruction", "pickup_change", "absence", "birthday_note", "medication", "incident_report":
                ChildrenView()
            default:
                NotificationDetailView(notification: notification)
            }
        }
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
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            await notificationInbox.refresh()
            notifications = notificationInbox.notifications
            errorMessage = notificationInbox.errorMessage
            if canCompose, let schoolId = appSession.activeSchool?.id {
                members = try await SchoolService.shared.fetchMembers(schoolId: schoolId)
            } else {
                members = []
            }
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load notifications", error)
            isLoading = false
        }
    }

    @MainActor
    private func markRead(_ notification: NotificationInboxItem) async {
        guard notification.readAt == nil else { return }
        await notificationInbox.markRead(notification)
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].readAt = Date()
        }
    }

    private func delete(_ notification: NotificationInboxItem) {
        guard deletingNotificationIDs.insert(notification.id).inserted else { return }
        Task { await dismiss(notification) }
    }

    @MainActor
    private func dismiss(_ notification: NotificationInboxItem) async {
        defer { deletingNotificationIDs.remove(notification.id) }
        guard let originalIndex = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        _ = withAnimation { notifications.remove(at: originalIndex) }

        let removed = await notificationInbox.dismiss(notification)
        if removed == false {
            withAnimation {
                notifications.insert(notification, at: min(originalIndex, notifications.endIndex))
            }
            errorMessage = notificationInbox.errorMessage
        } else {
            errorMessage = nil
        }
    }

    @MainActor
    private func dismissAll() async {
        guard isClearing == false else { return }
        isClearing = true
        let previousNotifications = notifications
        withAnimation { notifications = [] }

        let removed = await notificationInbox.dismissAll()
        if removed == false {
            withAnimation { notifications = previousNotifications }
            errorMessage = notificationInbox.errorMessage
        } else {
            errorMessage = nil
        }
        isClearing = false
    }
}

private extension View {
    func notificationListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
    }
}

private struct NotificationDetailView: View {
    let notification: NotificationInboxItem

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(notification.title)
                    .font(.largeTitle.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(notification.body)
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                Label(notification.schoolName, systemImage: "building.2")
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                if let createdAt = notification.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.48))
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SchoolNotificationComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let members: [SchoolMember]
    var onSent: () -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedRecipients = Set<UUID>()
    @State private var category = "school_announcement"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var eligibleMembers: [SchoolMember] {
        if appSession.role == .parent {
            return members.filter { $0.membership.role == .teacher || $0.membership.role.canManageSchool }
        }
        if appSession.role == .teacher {
            return members.filter { $0.membership.role == .parent }
        }
        return members
    }

    private var categories: [(String, String)] {
        switch appSession.role {
        case .parent:
            return [
                ("medicine_instruction", "Medicine Instruction"),
                ("pickup_change", "Pickup Change"),
                ("absence", "Absence / Day Off"),
                ("birthday_note", "Birthday Note")
            ]
        case .teacher, .schoolDirector, .hqDirector:
            return [
                ("school_announcement", "School Announcement"),
                ("weather", "Weather"),
                ("birthday", "Birthday"),
                ("medication", "Medication"),
                ("supplies", "Clothes / Diapers / Wipes"),
                ("sickness", "Sickness"),
                ("bowel_movement", "Bowel Movement"),
                ("potty_training", "Potty Training"),
                ("incident_report", "Incident Report"),
                ("event_change", "Event Change"),
                ("training_assigned", "Training"),
                ("paperwork_due", "Paperwork")
            ]
        case .none:
            return [("school_announcement", "School Announcement")]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    TextField("Title", text: $title)
                    TextField("Body", text: $bodyText, axis: .vertical)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.0) { item in
                            Text(item.1).tag(item.0)
                        }
                    }
                }

                Section("Recipients") {
                    Button("Select All") {
                        selectedRecipients = Set(eligibleMembers.map(\.id))
                    }
                    ForEach(eligibleMembers) { member in
                        Toggle(member.displayName, isOn: Binding(
                            get: { selectedRecipients.contains(member.id) },
                            set: { selected in
                                if selected {
                                    selectedRecipients.insert(member.id)
                                } else {
                                    selectedRecipients.remove(member.id)
                                }
                            }
                        ))
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Notification")
            .onAppear {
                if categories.contains(where: { $0.0 == category }) == false {
                    category = categories.first?.0 ?? "school_announcement"
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Sending" : "Send") { send() }
                        .disabled(title.isEmpty || bodyText.isEmpty || selectedRecipients.isEmpty || isSaving)
                }
            }
        }
    }

    private func send() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.createNotification(
                    schoolId: schoolId,
                    title: title,
                    body: bodyText,
                    category: category,
                    recipientIds: Array(selectedRecipients)
                )
                await MainActor.run {
                    isSaving = false
                    onSent()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not send notification", error)
                }
            }
        }
    }
}

#Preview {
    NotificationsView()
        .environmentObject(AppSessionManager())
        .environmentObject(NotificationInboxStore())
}
