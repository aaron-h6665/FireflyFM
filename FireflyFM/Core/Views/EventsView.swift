//
//  EventsView.swift
//  FireflyFM
//

import SwiftUI
import SDWebImageSwiftUI

struct EventsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var schools: [School] = []
    @State private var selectedSchoolId: UUID?
    @State private var events: [SchoolEvent] = []
    @State private var members: [SchoolMember] = []
    @State private var profilesById: [UUID: UserProfile] = [:]
    @State private var selectedMode: EventDisplayMode = .list
    @State private var displayMonth = Date()
    @State private var selectedDate = Date()
    @State private var showingCreation = false
    @State private var editingEvent: SchoolEvent?
    @State private var deletingEvent: SchoolEvent?
    @State private var showArchived = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var needsSchoolPicker: Bool {
        appSession.role == .hqDirector
    }

    private var effectiveSchoolId: UUID? {
        needsSchoolPicker ? selectedSchoolId : appSession.activeSchool?.id
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        schoolPicker
                        modePicker

                        if isLoading {
                            ProgressView().tint(AppConstants.Colors.accessibleYellow)
                        } else if needsSchoolPicker && schools.isEmpty {
                            emptyPanel("No schools are available yet.")
                        } else if events.isEmpty {
                            emptyPanel("No events scheduled.")
                        } else {
                            if selectedMode == .list {
                                listEvents
                            } else {
                                calendarEvents
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
                .refreshable { await loadEvents() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCreation) {
                if let schoolId = effectiveSchoolId {
                    SchoolEventEditorView(schoolId: schoolId, members: members, event: nil) {
                        Task { await loadEvents() }
                    }
                }
            }
            .sheet(item: $editingEvent) { event in
                SchoolEventEditorView(schoolId: event.schoolId, members: members, event: event) {
                    Task { await loadEvents() }
                }
            }
            .confirmationDialog(
                "Delete this event?",
                isPresented: Binding(
                    get: { deletingEvent != nil },
                    set: { if !$0 { deletingEvent = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Event", role: .destructive) {
                    deletePendingEvent()
                }
                Button("Cancel", role: .cancel) {
                    deletingEvent = nil
                }
            } message: {
                Text("This removes the event from the school calendar for everyone.")
            }
            .task(id: appSession.activeMembershipId) { await loadInitialData() }
        }
    }

    private var header: some View {
        HStack {
            Text("Events")
                .font(.largeTitle.bold())
                .foregroundColor(AppConstants.Colors.primaryText)

            Spacer()

            Button {
                withAnimation(.snappy) {
                    selectedMode = selectedMode == .list ? .calendar : .list
                }
            } label: {
                Image(systemName: selectedMode == .list ? "calendar" : "list.bullet")
                    .font(.system(size: 24))
                    .foregroundColor(AppConstants.Colors.primaryText)
            }

            if appSession.role?.canManageEvents == true {
                Button {
                    showingCreation = true
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(AppConstants.Colors.primaryText)
                }
            }
        }
    }

    private var modePicker: some View {
        VStack(spacing: 10) {
            Picker("Event View", selection: $selectedMode) {
                Text("List").tag(EventDisplayMode.list)
                Text("Calendar").tag(EventDisplayMode.calendar)
            }
            .pickerStyle(.segmented)

            if appSession.role?.canManageEvents == true {
                Toggle("Show archived events", isOn: $showArchived)
                    .font(.subheadline.bold())
                    .tint(AppConstants.Colors.primaryAction)
                    .onChange(of: showArchived) { _, _ in
                        Task { await loadEvents() }
                    }
            }
        }
    }

    @ViewBuilder
    private var schoolPicker: some View {
        if needsSchoolPicker && schools.isEmpty == false {
            HStack(spacing: 12) {
                Label("School", systemImage: "building.2")
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.secondaryText)

                Spacer()

                Picker("School", selection: Binding(
                    get: { selectedSchoolId ?? schools.first?.id },
                    set: { selectedSchoolId = $0 }
                )) {
                    ForEach(schools) { school in
                        Text(school.name).tag(Optional(school.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(AppConstants.Colors.primaryAction)
            }
            .padding()
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius))
            .onChange(of: selectedSchoolId) { _, _ in
                Task { await loadEvents() }
            }
        }
    }

    private var listEvents: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(monthGroups(for: events)) { group in
                monthSection(group)
            }
        }
    }

    private var calendarEvents: some View {
        VStack(alignment: .leading, spacing: 16) {
            CalendarMonthView(
                displayMonth: $displayMonth,
                selectedDate: $selectedDate,
                events: events
            )

            let monthEvents = events.filter { Calendar.current.isDate($0.startAt, equalTo: displayMonth, toGranularity: .month) }
            if monthEvents.isEmpty {
                emptyPanel("No events in \(displayMonth.formatted(.dateTime.month(.wide))).")
            } else {
                ForEach(monthGroups(for: monthEvents)) { group in
                    monthSection(group)
                }
            }
        }
    }

    private func monthSection(_ group: EventMonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            ForEach(group.events) { event in
                if appSession.role?.canManageEvents == true {
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            if event.archivedAt == nil {
                                editingEvent = event
                            }
                        } label: {
                            EventCardView(event: event, creator: event.createdBy.flatMap { profilesById[$0] })
                        }
                        .buttonStyle(.plain)

                        eventActionsMenu(for: event)
                    }
                    .contextMenu {
                        eventActionButtons(for: event)
                    }
                } else {
                    EventCardView(event: event, creator: event.createdBy.flatMap { profilesById[$0] })
                }
            }
        }
    }

    private func eventActionsMenu(for event: SchoolEvent) -> some View {
        Menu {
            eventActionButtons(for: event)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundColor(AppConstants.Colors.primaryText)
                .frame(width: 44, height: 44)
                .background(AppConstants.Colors.card)
                .clipShape(Circle())
        }
        .accessibilityLabel("Actions for \(event.title)")
    }

    @ViewBuilder
    private func eventActionButtons(for event: SchoolEvent) -> some View {
        if event.archivedAt == nil {
            Button {
                editingEvent = event
            } label: {
                Label("Edit Event", systemImage: "pencil")
            }
        }

        Button {
            setArchived(event, archived: event.archivedAt == nil)
        } label: {
            Label(
                event.archivedAt == nil ? "Archive Event" : "Restore Event",
                systemImage: event.archivedAt == nil ? "archivebox" : "arrow.uturn.backward.circle"
            )
        }

        Button(role: .destructive) {
            deletingEvent = event
        } label: {
            Label("Delete Event", systemImage: "trash")
        }
    }

    private func monthGroups(for events: [SchoolEvent]) -> [EventMonthGroup] {
        let grouped = Dictionary(grouping: events) { event in
            Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: event.startAt)) ?? event.startAt
        }

        return grouped.keys.sorted().map { month in
            EventMonthGroup(
                month: month,
                events: (grouped[month] ?? []).sorted { $0.startAt < $1.startAt }
            )
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
    private func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        do {
            if needsSchoolPicker {
                schools = try await SchoolService.shared.fetchSchoolsForHQ()
                if selectedSchoolId.flatMap({ selectedId in schools.first { $0.id == selectedId } }) == nil {
                    selectedSchoolId = schools.first?.id
                }
            } else {
                schools = []
                selectedSchoolId = nil
            }
            await loadEvents()
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            events = []
            members = []
            profilesById = [:]
            errorMessage = AppErrorMessage.school("Could not load schools", error)
            isLoading = false
        }
    }

    @MainActor
    private func loadEvents() async {
        guard let schoolId = effectiveSchoolId else {
            events = []
            members = []
            profilesById = [:]
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            events = try await SchoolWorkflowService.shared.fetchEvents(
                schoolId: schoolId,
                includeArchived: showArchived && appSession.role?.canManageEvents == true
            )
            if appSession.role?.canManageEvents == true {
                members = try await SchoolService.shared.fetchMembers(schoolId: schoolId)
            } else {
                members = []
            }
            profilesById = try await ProfileService.shared.fetchProfiles(ids: events.compactMap(\.createdBy))
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load events", error)
            isLoading = false
        }
    }

    private func deletePendingEvent() {
        guard let event = deletingEvent else { return }
        deletingEvent = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.deleteEvent(eventId: event.id)
                await loadEvents()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not delete event", error)
                }
            }
        }
    }

    private func setArchived(_ event: SchoolEvent, archived: Bool) {
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.setEventArchived(eventId: event.id, archived: archived)
                await loadEvents()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school(archived ? "Could not archive event" : "Could not restore event", error)
                }
            }
        }
    }
}

enum EventDisplayMode: String, CaseIterable, Identifiable {
    case list
    case calendar

    var id: String { rawValue }
}

struct EventMonthGroup: Identifiable {
    let month: Date
    let events: [SchoolEvent]

    var id: Date { month }

    var title: String {
        month.formatted(.dateTime.month(.wide).year())
    }
}

struct EventCardView: View {
    let event: SchoolEvent
    let creator: UserProfile?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(event.startAt.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Text(event.startAt.formatted(.dateTime.day()))
                    .font(.title2.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
            }
            .frame(width: 54, height: 58)
            .background(AppConstants.Colors.background.opacity(0.45))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 7) {
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)

                if event.archivedAt != nil {
                    Label("Archived", systemImage: "archivebox.fill")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                }

                Text(timeText)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)

                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    ProfileMiniView(profile: creator)
                    Text(creator?.displayName ?? "School Staff")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
                    if let repeatRule = event.repeatRule, repeatRule != "none" {
                        Text(repeatRule.capitalized)
                            .font(.caption2.bold())
                            .foregroundColor(AppConstants.Colors.brandNavy)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppConstants.Colors.accessibleYellow)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private var timeText: String {
        if event.allDay {
            return "All-day"
        }

        if let endAt = event.endAt {
            return "\(event.startAt.formatted(date: .omitted, time: .shortened)) - \(endAt.formatted(date: .omitted, time: .shortened))"
        }

        return event.startAt.formatted(date: .omitted, time: .shortened)
    }
}

struct ProfileMiniView: View {
    let profile: UserProfile?

    var body: some View {
        Group {
            if let avatarUrl = profile?.avatarUrl, let url = URL(string: avatarUrl) {
                WebImage(url: url)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.white.opacity(0.16))
                    .overlay(
                        Text(initials)
                            .font(.caption2.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                    )
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
    }

    private var initials: String {
        let name = profile?.displayName ?? "S"
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "S" : String(letters).uppercased()
    }
}

struct CalendarMonthView: View {
    @Binding var displayMonth: Date
    @Binding var selectedDate: Date
    let events: [SchoolEvent]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = Calendar.current.shortStandaloneWeekdaySymbols

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    moveMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(AppConstants.Colors.primaryText)
                }

                Spacer()

                Text(displayMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)

                Spacer()

                Button {
                    moveMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(AppConstants.Colors.primaryText)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday.uppercased())
                        .font(.caption2.bold())
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
                        .frame(height: 18)
                }

                ForEach(calendarDays, id: \.self) { date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private var calendarDays: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else { return [] }

        var days: [Date?] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            days.append(calendar.isDate(current, equalTo: displayMonth, toGranularity: .month) ? current : nil)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? lastWeek.end
        }
        return days
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let eventsForDay = events.filter { calendar.isDate($0.startAt, inSameDayAs: date) }

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.bold())
                    .foregroundColor(isSelected ? AppConstants.Colors.brandNavy : AppConstants.Colors.primaryText)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? AppConstants.Colors.accessibleYellow : isToday ? AppConstants.Colors.raised : Color.clear)
                    .clipShape(Circle())

                HStack(spacing: 2) {
                    ForEach(0..<min(eventsForDay.count, 3), id: \.self) { _ in
                        Circle()
                            .fill(AppConstants.Colors.accessibleYellow)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(height: 42)
        }
        .buttonStyle(.plain)
    }

    private func moveMonth(_ amount: Int) {
        displayMonth = calendar.date(byAdding: .month, value: amount, to: displayMonth) ?? displayMonth
    }
}

struct SchoolEventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let schoolId: UUID
    let members: [SchoolMember]
    let event: SchoolEvent?
    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var allDay = false
    @State private var startAt = Date()
    @State private var endAt = Date().addingTimeInterval(3600)
    @State private var repeatRule = "none"
    @State private var shareAsNotification = true
    @State private var selectedRecipients = Set<UUID>()
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(schoolId: UUID, members: [SchoolMember], event: SchoolEvent?, onSaved: @escaping () -> Void) {
        self.schoolId = schoolId
        self.members = members
        self.event = event
        self.onSaved = onSaved
        _title = State(initialValue: event?.title ?? "")
        _description = State(initialValue: event?.description ?? "")
        _allDay = State(initialValue: event?.allDay ?? false)
        _startAt = State(initialValue: event?.startAt ?? Date())
        _endAt = State(initialValue: event?.endAt ?? Date().addingTimeInterval(3600))
        _repeatRule = State(initialValue: event?.repeatRule ?? "none")
        _shareAsNotification = State(initialValue: event == nil)
    }

    private var isEditing: Bool {
        event != nil
    }

    private var eligibleMembers: [SchoolMember] {
        if appSession.role == .teacher {
            return members.filter { $0.membership.role == .parent }
        }
        return members
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                    Toggle("All-day", isOn: $allDay)
                    DatePicker("Starts", selection: $startAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $endAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    Picker("Repeat", selection: $repeatRule) {
                        Text("Never").tag("none")
                        Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly")
                        Text("Monthly").tag("monthly")
                        Text("Yearly").tag("yearly")
                    }
                }

                Section("Invite People") {
                    if isEditing {
                        Text("Invite changes apply when creating a new event. Existing event notifications are left unchanged.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Button("Select All") {
                            selectedRecipients = Set(eligibleMembers.map(\.id))
                        }
                        ForEach(eligibleMembers) { member in
                            Toggle(member.displayName, isOn: Binding(
                                get: { selectedRecipients.contains(member.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedRecipients.insert(member.id)
                                    } else {
                                        selectedRecipients.remove(member.id)
                                    }
                                }
                            ))
                        }
                    }
                }

                if !isEditing {
                    Section("Notifications") {
                    Toggle("Share as notification", isOn: $shareAsNotification)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle(isEditing ? "Edit Event" : "New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                if let event {
                    try await SchoolWorkflowService.shared.updateEvent(
                        eventId: event.id,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay,
                        repeatRule: repeatRule == "none" ? nil : repeatRule
                    )
                } else {
                    try await SchoolWorkflowService.shared.createEvent(
                        schoolId: schoolId,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay,
                        repeatRule: repeatRule == "none" ? nil : repeatRule,
                        invitedUserIds: Array(selectedRecipients),
                        shareAsNotification: shareAsNotification
                    )
                }
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school(isEditing ? "Could not update event" : "Could not create event", error)
                }
            }
        }
    }
}

#Preview {
    EventsView()
        .environmentObject(AppSessionManager())
}
