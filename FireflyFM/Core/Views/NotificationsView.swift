//
//  NotificationsView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var notifications: [AppNotification] = []
    @State private var members: [SchoolMember] = []
    @State private var showingComposer = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canCompose: Bool {
        appSession.role == .parent || appSession.role == .teacher || appSession.role?.canManageSchool == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header

                        Text(descriptionText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.65))

                        if isLoading {
                            ProgressView().tint(AppConstants.Colors.accessibleYellow)
                        } else if notifications.isEmpty {
                            emptyPanel("No notifications yet.")
                        } else {
                            ForEach(notifications) { notification in
                                NavigationLink {
                                    notificationDestination(notification)
                                } label: {
                                    notificationCard(notification)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingComposer) {
                SchoolNotificationComposerView(members: members) {
                    Task { await load() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            Spacer()

            if canCompose {
                Button {
                    showingComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var descriptionText: String {
        switch appSession.role {
        case .parent:
            "Send medicine, pickup, absence, and birthday notes; receive paperwork, child updates, receipts, events, newsletters, and school announcements."
        case .teacher:
            "Training, curriculum updates, director announcements, events, and child workflow reminders."
        case .schoolDirector, .hqDirector:
            "Submissions, flagged paperwork, teacher training, invite usage, and school-wide alerts."
        case .none:
            "School notifications."
        }
    }

    private func notificationCard(_ notification: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(notification.title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(notification.category.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppConstants.Colors.accessibleYellow)
                    .clipShape(Capsule())
            }
            Text(notification.body)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            if let createdAt = notification.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    @ViewBuilder
    private func notificationDestination(_ notification: AppNotification) -> some View {
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
            case "assignment_assigned", "assignment_submitted", "assignment_reviewed":
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
            .foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
    }

    @MainActor
    private func load() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await SchoolWorkflowService.shared.fetchNotifications(schoolId: schoolId)
            notifications = appSession.role?.canManageSchool == true
                ? loaded.filter { $0.category != "paperwork_due" }
                : loaded
            if canCompose {
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
}

private struct NotificationDetailView: View {
    let notification: AppNotification

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(notification.title)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text(notification.body)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.72))
                if let createdAt = notification.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.48))
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
}
