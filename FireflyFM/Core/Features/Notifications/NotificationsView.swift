//
//  NotificationsView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct NotificationsView: View {
    private enum InboxFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case unread = "Unread"

        var id: Self { self }
    }

    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var notificationInbox: NotificationInboxStore

    @State private var model = NotificationInboxModel()
    @State private var notifications: [NotificationInboxItem] = []
    @State private var showingComposer = false
    @State private var showingPreferences = false
    @State private var showingClearConfirmation = false
    @State private var isClearing = false
    @State private var isMarkingAllRead = false
    @State private var deletingNotificationIDs = Set<UUID>()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var focusedNotification: NotificationInboxItem?
    @State private var inboxFilter: InboxFilter = .all

    let focusNotificationId: UUID?

    init(focusNotificationId: UUID? = nil) {
        self.focusNotificationId = focusNotificationId
    }

    private var canCompose: Bool {
        NotificationAccessPolicy(context: appSession.accessContext()).canCompose
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
                        Picker("Notification filter", selection: $inboxFilter) {
                            ForEach(InboxFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Show all or unread notifications")
                        .notificationListRow()

                        Text(descriptionText)
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.secondaryText)
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
                        } else if filteredNotifications.isEmpty {
                            emptyPanel(inboxFilter == .unread ? "You’re all caught up." : "No notifications yet.")
                                .notificationListRow()
                        } else {
                            ForEach(groupedNotificationDays, id: \.self) { day in
                                Section {
                                    ForEach(notifications(on: day)) { notification in
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
                                } header: {
                                    Text(dayLabel(day))
                                        .font(.caption.bold())
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                        .textCase(nil)
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
            .navigationDestination(item: $focusedNotification) { notification in
                notificationDestination(notification)
                    .task { await markRead(notification) }
            }
            .sheet(isPresented: $showingComposer) {
                SchoolNotificationComposerView(members: model.members) {
                    Task { await load() }
                }
            }
            .sheet(isPresented: $showingPreferences) { NotificationPreferencesView() }
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
                Button { showingPreferences = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppConstants.Colors.primaryAction)
                        .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                        .background(AppConstants.Colors.card)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notification preferences")

                Menu {
                    Button("Delete all", systemImage: "trash", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .disabled(notifications.isEmpty || isClearing || isMarkingAllRead)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppConstants.Colors.primaryAction)
                        .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                        .background(AppConstants.Colors.card)
                        .clipShape(Circle())
                }
                .accessibilityLabel("More notification actions")
            }

            HStack {
                Text(notificationSummary)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.secondaryText)

                Spacer()

                if unreadCount > 0 || isMarkingAllRead {
                    Button {
                        Task { await markAllRead() }
                    } label: {
                        HStack(spacing: 7) {
                            if isMarkingAllRead {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                            Text(isMarkingAllRead ? "Marking read" : "Mark all read")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                        .frame(minHeight: AppConstants.Layout.minimumTapTarget)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isClearing || isMarkingAllRead || deletingNotificationIDs.isEmpty == false)
                    .accessibilityLabel(isMarkingAllRead ? "Marking notifications read" : "Mark all notifications read")
                }
            }
        }
    }

    private var notificationSummary: String {
        if isClearing {
            return "Removing notifications…"
        }
        switch unreadCount {
        case 0:
            return "You’re all caught up"
        case 1:
            return "1 unread notification"
        default:
            return "\(unreadCount) unread notifications"
        }
    }

    private var unreadCount: Int {
        notifications.lazy.filter { $0.readAt == nil }.count
    }

    private var filteredNotifications: [NotificationInboxItem] {
        switch inboxFilter {
        case .all: notifications
        case .unread: notifications.filter { $0.readAt == nil }
        }
    }

    private var groupedNotificationDays: [Date] {
        let calendar = Calendar.current
        return Set(filteredNotifications.map { notification in
            calendar.startOfDay(for: notification.createdAt ?? .distantPast)
        }).sorted(by: >)
    }

    private func notifications(on day: Date) -> [NotificationInboxItem] {
        let calendar = Calendar.current
        return filteredNotifications.filter {
            calendar.startOfDay(for: $0.createdAt ?? .distantPast) == day
        }
    }

    private func dayLabel(_ day: Date) -> String {
        guard day != Calendar.current.startOfDay(for: .distantPast) else { return "Earlier" }
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.wide).day().year())
    }

    private var descriptionText: String {
        NotificationAccessPolicy(context: appSession.accessContext()).inboxDescription
    }

    private func notificationCard(_ notification: NotificationInboxItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: categorySymbol(for: notification))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(categoryColor(for: notification))
                .frame(width: 38, height: 38)
                .background(categoryColor(for: notification).opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(notification.title)
                        .font(notification.readAt == nil ? .headline : .subheadline.weight(.semibold))
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(notification.readAt == nil ? 1 : 0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if notification.readAt == nil {
                        Circle()
                            .fill(AppConstants.Colors.accessibleYellow)
                            .frame(width: 9, height: 9)
                            .accessibilityLabel("Unread")
                    }
                }
                Text(notification.body)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(notification.readAt == nil ? 0.72 : 0.55))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Text(notification.category.replacingOccurrences(of: "_", with: " ").capitalized)
                    Text("•")
                    Text(notification.schoolName)
                    if let createdAt = notification.createdAt {
                        Text("•")
                        Text(createdAt.formatted(date: .omitted, time: .shortened))
                    }
                }
                .font(.caption)
                .foregroundColor(AppConstants.Colors.secondaryText)
                .lineLimit(1)
            }
        }
        .padding(16)
        .background(AppConstants.Colors.card.opacity(notification.readAt == nil ? 1 : 0.7))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
    }

    private func categorySymbol(for notification: NotificationInboxItem) -> String {
        switch notification.route?.type ?? notification.sourceType ?? notification.category {
        case "assignment", "paperwork_assignment", "training_assignment": "checklist"
        case "school_event", "event_change": "calendar"
        case "chat_room": "message.fill"
        case "attendance_session": "person.crop.circle.badge.checkmark"
        case "medication_task", "medication_instruction", "medication", "medicine_instruction": "pills.fill"
        case "child_connection_request": "link.badge.plus"
        case "family_request", "pickup_change", "absence": "person.crop.circle.badge.questionmark"
        case "child_care_event", "child_feed", "child_update": "figure.and.child.holdinghands"
        default: "bell.fill"
        }
    }

    private func categoryColor(for notification: NotificationInboxItem) -> Color {
        switch notification.priority {
        case "urgent", "critical": .red
        default: AppConstants.Colors.primaryAction
        }
    }

    @ViewBuilder
    private func notificationDestination(_ notification: NotificationInboxItem) -> some View {
        switch NotificationDestinationResolver().resolve(notification) {
        case .assignment(let assignmentId):
            AssignmentDetailView(assignmentId: assignmentId) {
                Task { await load() }
            }
        case .paperwork:
            PaperworkView()
        case .events:
            EventsView()
        case .training:
            CurriculumView()
        case .childConnection:
            if let school = appSession.activeSchool {
                if ChildAccessPolicy(context: appSession.accessContext()).canManageConnections {
                    ChildConnectionReviewView(school: school) { Task { await load() } }
                } else {
                    ChildConnectionView(school: school) { Task { await load() } }
                }
            } else { NotificationDetailView(notification: notification) }
        case .attendance(let sessionId):
            AttendanceView(focusSessionId: sessionId)
        case .childChat(let childId):
            ChildChatNotificationDestination(childId: childId)
        case .childCareEvent(let eventId):
            ChildCareNotificationDestination(eventId: eventId)
        case .childProfile(let childId):
            ChildProfileNotificationDestination(childId: childId)
        case .familyRequests(let requestId):
            FamilyRequestsView(focusRequestId: requestId)
        case .care:
            CareTodayView()
        case .chatRoom(let roomId):
            ChatRoomNotificationDestination(roomId: roomId)
        case .detail:
            NotificationDetailView(notification: notification)
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
            if let focusNotificationId, focusedNotification == nil {
                focusedNotification = notifications.first { $0.id == focusNotificationId }
                if focusedNotification == nil { errorMessage = "This notification is no longer available." }
            }
            if let inboxError = notificationInbox.errorMessage {
                errorMessage = inboxError
            }
            try await model.loadDirectory(
                schoolId: appSession.activeSchool?.id,
                canCompose: canCompose
            )
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
        if await notificationInbox.markRead(notification) {
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications[index].readAt = Date()
            }
            errorMessage = nil
        } else {
            errorMessage = notificationInbox.errorMessage
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
    private func markAllRead() async {
        guard isMarkingAllRead == false, unreadCount > 0 else { return }
        isMarkingAllRead = true
        let previousNotifications = notifications
        let readAt = Date()
        for index in notifications.indices where notifications[index].readAt == nil {
            notifications[index].readAt = readAt
        }

        let marked = await notificationInbox.markAllRead()
        if marked == false {
            notifications = previousNotifications
            errorMessage = notificationInbox.errorMessage
        } else {
            errorMessage = nil
        }
        isMarkingAllRead = false
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

private struct NotificationPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = NotificationPreferencesModel()
    @State private var enabled: [String: Bool] = [:]
    @State private var quietHoursEnabled = false
    @State private var quietStart = Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
    @State private var quietEnd = Calendar.current.date(from: DateComponents(hour: 7)) ?? Date()

    private let categories: [PreferenceCategory] = [
        .init(key: "assignments", title: "Assignments & onboarding", symbol: "checklist"),
        .init(key: "attendance", title: "Attendance & daily summaries", symbol: "calendar.badge.checkmark"),
        .init(key: "chat", title: "Chat", symbol: "message.fill"),
        .init(key: "connections", title: "Child connections", symbol: "link.badge.plus"),
        .init(key: "family_requests", title: "Family requests", symbol: "person.crop.circle.badge.questionmark"),
        .init(key: "announcements", title: "School announcements", symbol: "megaphone.fill"),
        .init(key: "medication", title: "Medication safety", symbol: "pills.fill", safetyCritical: true),
        .init(key: "health", title: "Health alerts", symbol: "cross.case.fill", safetyCritical: true)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Categories") {
                    ForEach(categories) { category in
                        Toggle(isOn: Binding(
                            get: { category.safetyCritical || enabled[category.key, default: true] },
                            set: { enabled[category.key] = category.safetyCritical ? true : $0 }
                        )) {
                            Label(category.title, systemImage: category.symbol)
                        }
                        .disabled(category.safetyCritical)
                        if category.safetyCritical {
                            Text("Safety-critical alerts always remain enabled.").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Section("Quiet hours") {
                    Toggle("Delay routine notifications", isOn: $quietHoursEnabled)
                    if quietHoursEnabled {
                        DatePicker("Starts", selection: $quietStart, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $quietEnd, displayedComponents: .hourAndMinute)
                    }
                    Text("Urgent medication and health alerts are delivered immediately. Room-specific chat muting remains in each room’s settings.")
                        .font(.caption).foregroundColor(.secondary)
                }
                if model.isLoading { ProgressView() }
                if let errorMessage = model.errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("Notification Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "Saving…" : "Save") { save() }
                        .disabled(model.isLoading || model.isSaving)
                }
            }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        await model.load()
        for preference in model.preferences { enabled[preference.category] = preference.enabled }
        if let saved = model.preferences.first(where: { $0.quietHoursStart != nil && $0.quietHoursEnd != nil }),
           let start = Self.time(from: saved.quietHoursStart),
           let end = Self.time(from: saved.quietHoursEnd) {
            quietHoursEnabled = true
            quietStart = start
            quietEnd = end
        }
    }

    private func save() {
        Task {
            let drafts = categories.map { category in
                NotificationPreferenceDraft(
                    category: category.key,
                    enabled: category.safetyCritical || enabled[category.key, default: true]
                )
            }
            if await model.save(
                drafts: drafts,
                quietHoursStart: quietHoursEnabled ? Self.timeString(from: quietStart) : nil,
                quietHoursEnd: quietHoursEnabled ? Self.timeString(from: quietEnd) : nil
            ) {
                dismiss()
            }
        }
    }

    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d:00", components.hour ?? 0, components.minute ?? 0)
    }

    private static func time(from value: String?) -> Date? {
        guard let value else { return nil }
        let pieces = value.split(separator: ":").compactMap { Int($0) }
        guard pieces.count >= 2 else { return nil }
        return Calendar.current.date(from: DateComponents(hour: pieces[0], minute: pieces[1]))
    }
}

private struct PreferenceCategory: Identifiable {
    let key: String
    let title: String
    let symbol: String
    var safetyCritical = false
    var id: String { key }
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

private struct ChildCareNotificationDestination: View {
    let eventId: UUID
    @State private var model = ChildCareNotificationModel()

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            if let event = model.event {
                VStack(alignment: .leading, spacing: 14) {
                    Label(event.eventType.title, systemImage: event.eventType.symbol).font(.largeTitle.bold())
                    Text(model.child?.fullName ?? "Child").font(.title3.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
                    Text(event.occurredAt.formatted(date: .complete, time: .shortened)).foregroundColor(AppConstants.Colors.secondaryText)
                    ForEach(event.details.keys.sorted(), id: \.self) { key in
                        if let value = event.details[key]?.stringValue, !value.isEmpty {
                            LabeledContent(key.replacingOccurrences(of: "_", with: " ").capitalized, value: value)
                        }
                    }
                    if let child = model.child { NavigationLink("Open Child Profile") { ChildProfileView(child: child) }.buttonStyle(.borderedProminent) }
                    Spacer()
                }.padding()
            } else if let errorMessage = model.errorMessage {
                ContentUnavailableView("Care event unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else { ProgressView().tint(AppConstants.Colors.accessibleYellow) }
        }
        .navigationTitle("Care Event")
        .task(id: eventId) { await model.load(eventId: eventId) }
    }
}

private struct ChildProfileNotificationDestination: View {
    let childId: UUID
    @State private var model = NotificationLookupModel()

    var body: some View {
        Group {
            if let child = model.child { ChildProfileView(child: child) }
            else if let errorMessage = model.errorMessage {
                ContentUnavailableView("Child profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(errorMessage))
            } else { ProgressView().tint(AppConstants.Colors.accessibleYellow) }
        }
        .task(id: childId) { await model.load(.child(childId)) }
    }
}

private struct ChatRoomNotificationDestination: View {
    let roomId: UUID
    @State private var model = NotificationLookupModel()

    var body: some View {
        Group {
            if let room = model.room { ChatRoomScreen(room: room) }
            else if let errorMessage = model.errorMessage { ContentUnavailableView("Chat unavailable", systemImage: "bubble.left.and.exclamationmark.bubble.right", description: Text(errorMessage)) }
            else { ProgressView().tint(AppConstants.Colors.accessibleYellow) }
        }
        .task(id: roomId) { await model.load(.chatRoom(roomId)) }
    }
}

private struct ChildChatNotificationDestination: View {
    let childId: UUID
    @State private var model = NotificationLookupModel()

    var body: some View {
        Group {
            if let room = model.room {
                ChatRoomScreen(room: room)
            } else if let errorMessage = model.errorMessage {
                ContentUnavailableView(
                    "Family chat unavailable",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Opening family chat")
                    .tint(AppConstants.Colors.primaryAction)
            }
        }
        .task(id: childId) { await model.load(.familyChat(childId)) }
    }
}

private struct SchoolNotificationComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let members: [SchoolDirectoryEntry]
    var onSent: () -> Void

    @State private var model = NotificationComposerModel()
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedRecipients = Set<UUID>()

    private var eligibleMembers: [SchoolDirectoryEntry] { members }

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    TextField("Title", text: $title)
                    TextField("Body", text: $bodyText, axis: .vertical)
                    Text("Director announcement").font(.caption).foregroundColor(.secondary)
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

                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("School Announcement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSending ? "Sending" : "Send") { send() }
                        .disabled(title.isEmpty || bodyText.isEmpty || selectedRecipients.isEmpty || model.isSending)
                }
            }
        }
    }

    private func send() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        Task {
            if await model.send(
                schoolId: schoolId,
                title: title,
                body: bodyText,
                recipientIds: Array(selectedRecipients)
            ) {
                onSent()
                dismiss()
            }
        }
    }
}

#Preview {
    NotificationsView()
        .environmentObject(AppSessionManager())
        .environmentObject(NotificationInboxStore())
}
