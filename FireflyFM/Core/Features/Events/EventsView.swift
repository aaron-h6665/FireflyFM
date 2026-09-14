import SDWebImageSwiftUI
import SwiftUI

enum EventDisplayMode: String, CaseIterable, Identifiable {
    case list
    case calendar

    var id: String { rawValue }
}

struct EventsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @Binding private var focusedEventId: UUID?
    @State private var model = EventCatalogModel()
    @State private var selectedSchoolId: UUID?
    @State private var selectedMode: EventDisplayMode = .list
    @State private var displayMonth = Date()
    @State private var selectedDate = Date()
    @State private var showingCreation = false
    @State private var selectedEvent: SchoolEvent?
    @State private var editingEvent: SchoolEvent?
    @State private var deletingEvent: SchoolEvent?
    @State private var showArchived = false

    private var accessPolicy: EventAccessPolicy {
        EventAccessPolicy(context: appSession.accessContext(selectedSchoolId: selectedSchoolId))
    }

    private var effectiveSchoolId: UUID? {
        accessPolicy.canSelectSchool ? selectedSchoolId : appSession.activeSchool?.id
    }

    init(focusedEventId: Binding<UUID?> = .constant(nil)) {
        _focusedEventId = focusedEventId
    }

    var body: some View {
        NavigationStack {
            FireflyScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                        header
                        schoolPicker
                        modePicker
                        content

                        if let message = model.mutationError {
                            FireflyInlineError(message: message)
                        }
                        if case .failed(let message) = model.phase {
                            FireflyInlineError(message: message)
                        }
                    }
                    .padding(FireflyTheme.Layout.cardPadding)
                }
                .refreshable { await loadEvents() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCreation) {
                if let schoolId = effectiveSchoolId {
                    SchoolEventEditorView(
                        schoolId: schoolId,
                        schools: accessPolicy.canSelectSchool ? model.schools : [],
                        members: model.members,
                        event: nil
                    ) {
                        Task { await model.reload() }
                    }
                }
            }
            .sheet(item: $editingEvent) { event in
                SchoolEventEditorView(schoolId: event.schoolId, members: model.members, event: event) {
                    Task { await model.reload() }
                }
            }
            .navigationDestination(item: $selectedEvent) { event in
                SchoolEventDetailView(
                    event: event,
                    creator: event.createdBy.flatMap { model.profilesById[$0] },
                    canManage: accessPolicy.canManage,
                    onEdit: { editingEvent = event }
                )
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
                    guard let event = deletingEvent else { return }
                    deletingEvent = nil
                    Task { await model.delete(event) }
                }
                Button("Cancel", role: .cancel) { deletingEvent = nil }
            } message: {
                Text("This removes the event from the school calendar for everyone.")
            }
            .task(id: appSession.activeMembershipId) {
                await loadInitialData()
                presentFocusedEventIfAvailable()
            }
            .onChange(of: focusedEventId) { _, _ in
                presentFocusedEventIfAvailable()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Events")
                .font(.largeTitle.bold())
                .foregroundColor(FireflyTheme.Colors.primaryText)
            Spacer()
            Button {
                withAnimation(.snappy) {
                    selectedMode = selectedMode == .list ? .calendar : .list
                }
            } label: {
                Image(systemName: selectedMode == .list ? "calendar" : "list.bullet")
                    .font(.title2)
                    .foregroundColor(FireflyTheme.Colors.primaryText)
                    .frame(
                        width: FireflyTheme.Layout.minimumTapTarget,
                        height: FireflyTheme.Layout.minimumTapTarget
                    )
            }
            .accessibilityLabel(selectedMode == .list ? "Show calendar" : "Show event list")

            if accessPolicy.canManage {
                Button {
                    showingCreation = true
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundColor(FireflyTheme.Colors.primaryText)
                        .frame(
                            width: FireflyTheme.Layout.minimumTapTarget,
                            height: FireflyTheme.Layout.minimumTapTarget
                        )
                }
                .disabled(effectiveSchoolId == nil)
                .accessibilityLabel("Create event")
            }
        }
    }

    private var modePicker: some View {
        VStack(spacing: FireflyTheme.Layout.spacingSmall) {
            Picker("Event View", selection: $selectedMode) {
                Text("List").tag(EventDisplayMode.list)
                Text("Calendar").tag(EventDisplayMode.calendar)
            }
            .pickerStyle(.segmented)

            if accessPolicy.canManage {
                Toggle("Show archived events", isOn: $showArchived)
                    .font(.subheadline.bold())
                    .tint(FireflyTheme.Colors.primaryAction)
                    .onChange(of: showArchived) { _, _ in
                        Task { await loadEvents() }
                    }
            }
        }
    }

    @ViewBuilder
    private var schoolPicker: some View {
        if accessPolicy.canSelectSchool, model.schools.isEmpty == false {
            FireflySchoolPicker(schools: model.schools, selectedSchoolId: $selectedSchoolId)
                .onChange(of: selectedSchoolId) { _, _ in
                    Task { await loadEvents() }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.phase.isLoading {
            ProgressView()
                .tint(FireflyTheme.Colors.primaryAction)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if accessPolicy.canSelectSchool && model.schools.isEmpty {
            FireflyEmptyState(title: "No schools are available yet", systemImage: "building.2")
        } else if model.events.isEmpty {
            FireflyEmptyState(title: "No events scheduled", systemImage: "calendar")
        } else if selectedMode == .list {
            listEvents
        } else {
            calendarEvents
        }
    }

    private var listEvents: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.cardPadding) {
            ForEach(model.monthGroups()) { group in
                monthSection(group)
            }
        }
    }

    private var calendarEvents: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.cardPadding) {
            CalendarMonthView(
                displayMonth: $displayMonth,
                selectedDate: $selectedDate,
                events: model.events
            )

            let monthEvents = model.events.filter {
                Calendar.current.isDate($0.startAt, equalTo: displayMonth, toGranularity: .month)
            }
            if monthEvents.isEmpty {
                FireflyEmptyState(
                    title: "No events in \(displayMonth.formatted(.dateTime.month(.wide)))",
                    systemImage: "calendar"
                )
            } else {
                ForEach(model.monthGroups(for: monthEvents)) { group in
                    monthSection(group)
                }
            }
        }
    }

    private func monthSection(_ group: EventMonthGroup) -> some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) {
            Text(group.title)
                .font(.headline)
                .foregroundColor(FireflyTheme.Colors.primaryAction)

            ForEach(group.events) { event in
                HStack(alignment: .top, spacing: FireflyTheme.Layout.spacingSmall) {
                    Button {
                        selectedEvent = event
                    } label: {
                        EventCardView(event: event, creator: event.createdBy.flatMap { model.profilesById[$0] })
                    }
                    .buttonStyle(.plain)

                    if accessPolicy.canManage {
                        eventActionsMenu(for: event)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func eventActionsMenu(for event: SchoolEvent) -> some View {
        Menu {
            eventActionButtons(for: event)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundColor(FireflyTheme.Colors.primaryText)
                .frame(
                    width: FireflyTheme.Layout.minimumTapTarget,
                    height: FireflyTheme.Layout.minimumTapTarget
                )
                .background(FireflyTheme.Colors.card)
                .clipShape(Circle())
        }
        .accessibilityLabel("Actions for \(event.title)")
    }

    @ViewBuilder
    private func eventActionButtons(for event: SchoolEvent) -> some View {
        if event.archivedAt == nil {
            Button("Edit Event", systemImage: "pencil") { editingEvent = event }
        }
        Button(
            event.archivedAt == nil ? "Archive Event" : "Restore Event",
            systemImage: event.archivedAt == nil ? "archivebox" : "arrow.uturn.backward.circle"
        ) {
            Task { await model.setArchived(event, archived: event.archivedAt == nil) }
        }
        Button("Delete Event", systemImage: "trash", role: .destructive) {
            deletingEvent = event
        }
    }

    private func loadInitialData() async {
        if accessPolicy.canSelectSchool {
            await model.loadSchools()
            if selectedSchoolId.flatMap({ selectedId in model.schools.first { $0.id == selectedId } }) == nil {
                selectedSchoolId = model.schools.first?.id
            }
        } else {
            selectedSchoolId = nil
        }
        await loadEvents()
    }

    private func loadEvents() async {
        guard let schoolId = effectiveSchoolId else { return }
        await model.load(
            schoolId: schoolId,
            canManage: accessPolicy.canManage,
            includeArchived: showArchived
        )
        presentFocusedEventIfAvailable()
    }

    private func presentFocusedEventIfAvailable() {
        guard
            let focusedEventId,
            let event = model.events.first(where: { $0.id == focusedEventId })
        else { return }

        selectedMode = .calendar
        displayMonth = event.startAt
        selectedDate = event.startAt
        selectedEvent = event
        self.focusedEventId = nil
    }
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

struct SchoolEventDetailView: View {
    let event: SchoolEvent
    let creator: UserProfile?
    let canManage: Bool
    var onEdit: () -> Void

    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingLarge) {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) {
                        Text(event.title)
                            .font(.largeTitle.bold())
                            .foregroundColor(FireflyTheme.Colors.primaryText)

                        Label(dateText, systemImage: "calendar")
                        Label(timeText, systemImage: "clock")

                        if let repeatRule = event.repeatRule, repeatRule != "none" {
                            Label(repeatRule.capitalized, systemImage: "repeat")
                        }
                    }
                    .foregroundColor(FireflyTheme.Colors.secondaryText)

                    FireflySectionCard {
                        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) {
                            Text("Description")
                                .font(.headline)
                                .foregroundColor(FireflyTheme.Colors.primaryText)
                            Text(event.description?.nilIfBlank ?? "No additional description was provided.")
                                .font(.body)
                                .foregroundColor(FireflyTheme.Colors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    HStack(spacing: FireflyTheme.Layout.spacingSmall) {
                        ProfileMiniView(profile: creator)
                        Text("Created by \(creator?.displayName ?? "School Staff")")
                            .font(.caption)
                            .foregroundColor(FireflyTheme.Colors.secondaryText)
                    }
                }
                .padding(FireflyTheme.Layout.cardPadding)
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManage && event.archivedAt == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit", action: onEdit)
                }
            }
        }
    }

    private var dateText: String {
        if let endAt = event.endAt,
           Calendar.current.isDate(event.startAt, inSameDayAs: endAt) == false {
            return "\(event.startAt.formatted(date: .abbreviated, time: .omitted)) – \(endAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return event.startAt.formatted(date: .complete, time: .omitted)
    }

    private var timeText: String {
        if event.allDay { return "All-day" }
        if let endAt = event.endAt {
            return "\(event.startAt.formatted(date: .omitted, time: .shortened)) – \(endAt.formatted(date: .omitted, time: .shortened))"
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

private enum EventSchoolTarget: String, CaseIterable, Identifiable {
    case one
    case selected
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: "One"
        case .selected: "Choose"
        case .all: "All"
        }
    }
}

struct EventRecipientSelectionKey: Hashable {
    let schoolId: UUID
    let userId: UUID
}

struct EventMemberOption: Identifiable {
    let member: SchoolMember
    let schoolName: String?

    var id: EventRecipientSelectionKey {
        EventRecipientSelectionKey(
            schoolId: member.membership.schoolId,
            userId: member.id
        )
    }

    var sortKey: String {
        member.displayName.lowercased() + "-" + (schoolName?.lowercased() ?? "")
    }

    func label(includesSchool: Bool) -> String {
        let roleTitle = member.membership.role.title
        let person = "\(member.displayName) · \(roleTitle)"
        guard includesSchool, let schoolName else { return person }
        return "\(person) · \(schoolName)"
    }
}

struct SchoolEventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let schoolId: UUID
    let schools: [School]
    let members: [SchoolMember]
    let event: SchoolEvent?
    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var allDay = false
    @State private var startAt = Date()
    @State private var endAt = Date().addingTimeInterval(3600)
    @State private var repeatRule = "none"
    @State private var invitesEveryone = true
    @State private var schoolTarget: EventSchoolTarget = .one
    @State private var selectedSchoolId: UUID
    @State private var selectedSchoolIds: Set<UUID>
    @State private var selectedRecipientKeys = Set<EventRecipientSelectionKey>()
    @State private var showingRecipientPicker = false
    @State private var mutationKey = UUID().uuidString
    @State private var model = EventEditorModel()

    init(
        schoolId: UUID,
        schools: [School] = [],
        members: [SchoolMember],
        event: SchoolEvent?,
        onSaved: @escaping () -> Void
    ) {
        self.schoolId = schoolId
        self.schools = schools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.members = members
        self.event = event
        self.onSaved = onSaved
        _title = State(initialValue: event?.title ?? "")
        _description = State(initialValue: event?.description ?? "")
        _allDay = State(initialValue: event?.allDay ?? false)
        _startAt = State(initialValue: event?.startAt ?? Date())
        _endAt = State(initialValue: event?.endAt ?? Date().addingTimeInterval(3600))
        _repeatRule = State(initialValue: event?.repeatRule ?? "none")
        let initialSchoolId = schools.contains(where: { $0.id == schoolId }) ? schoolId : (schools.first?.id ?? schoolId)
        _selectedSchoolId = State(initialValue: initialSchoolId)
        _selectedSchoolIds = State(initialValue: [initialSchoolId])
    }

    private var isEditing: Bool {
        event != nil
    }

    private var supportsMultipleSchools: Bool {
        schools.count > 1 && event == nil
    }

    private var destinationSchoolIds: [UUID] {
        guard supportsMultipleSchools else { return [schoolId] }
        switch schoolTarget {
        case .one:
            return [selectedSchoolId]
        case .selected:
            return schools.filter { selectedSchoolIds.contains($0.id) }.map(\.id)
        case .all:
            return schools.map(\.id)
        }
    }

    private var destinationSchoolCountText: String {
        destinationSchoolIds.count == 1 ? "1 school" : "\(destinationSchoolIds.count) schools"
    }

    private var deliverableSchoolIds: [UUID] {
        if invitesEveryone {
            return destinationSchoolIds
        }
        return destinationSchoolIds.filter { schoolId in
            selectedRecipientKeys.contains { $0.schoolId == schoolId }
        }
    }

    private var skippedSchools: [School] {
        guard supportsMultipleSchools, invitesEveryone == false else { return [] }
        return schools.filter { school in
            destinationSchoolIds.contains(school.id)
                && selectedRecipientKeys.contains(where: { $0.schoolId == school.id }) == false
        }
    }

    private func members(for targetSchoolId: UUID) -> [SchoolMember] {
        if let loaded = model.membersBySchool[targetSchoolId], loaded.isEmpty == false {
            return loaded
        }
        if targetSchoolId == schoolId {
            return members
        }
        return []
    }

    private func eligibleMembers(for targetSchoolId: UUID) -> [SchoolMember] {
        let policy = EventAccessPolicy(context: appSession.accessContext(selectedSchoolId: targetSchoolId))
        return members(for: targetSchoolId).filter { policy.canInvite(memberRole: $0.membership.role) }
    }

    private var allEligibleMemberOptions: [EventMemberOption] {
        destinationSchoolIds.flatMap { destinationId in
            let schoolName = schools.first(where: { $0.id == destinationId })?.name
            return eligibleMembers(for: destinationId).map { member in
                EventMemberOption(member: member, schoolName: schoolName)
            }
        }
    }

    private var canSave: Bool {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              model.isSaving == false else { return false }
        if isEditing { return true }
        guard destinationSchoolIds.isEmpty == false else { return false }
        if invitesEveryone { return true }
        return deliverableSchoolIds.isEmpty == false
    }

    var body: some View {
        NavigationStack {
            Form {
                schoolTargetSection

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
                        Button {
                            showingRecipientPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Label("Choose Audience", systemImage: "person.2")
                                Spacer()
                                Text(invitationSummary)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Everyone you choose will receive an event notification automatically.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        if invitesEveryone == false && selectedRecipientKeys.isEmpty {
                            Label("Choose at least one person.", systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        } else {
                            skippedSchoolsWarning
                        }
                    }
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle(isEditing ? "Edit Event" : "New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "Saving" : "Save") { save() }
                        .disabled(canSave == false)
                }
            }
            .task {
                if supportsMultipleSchools {
                    await model.loadMembers(schoolIds: schools.map(\.id))
                }
            }
            .onChange(of: schoolTarget) { _, _ in normalizeSchoolTarget() }
            .onChange(of: selectedSchoolId) { _, _ in normalizeSchoolTarget() }
            .onChange(of: selectedSchoolIds) { _, _ in normalizeSchoolTarget() }
            .sheet(isPresented: $showingRecipientPicker) {
                EventInviteAudiencePicker(
                    options: allEligibleMemberOptions,
                    isMultiSchool: destinationSchoolIds.count > 1,
                    invitesEveryone: $invitesEveryone,
                    selectedRecipientKeys: $selectedRecipientKeys
                )
            }
        }
    }

    @ViewBuilder
    private var schoolTargetSection: some View {
        if supportsMultipleSchools {
            Section("Schools") {
                Picker("Send To", selection: $schoolTarget) {
                    ForEach(EventSchoolTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("event-school-target")

                if schoolTarget == .one {
                    Picker("School", selection: $selectedSchoolId) {
                        ForEach(schools) { school in
                            Text(school.name).tag(school.id)
                        }
                    }
                } else if schoolTarget == .selected {
                    ForEach(schools) { school in
                        Toggle(school.name, isOn: Binding(
                            get: { selectedSchoolIds.contains(school.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedSchoolIds.insert(school.id)
                                } else {
                                    selectedSchoolIds.remove(school.id)
                                }
                            }
                        ))
                        .accessibilityIdentifier("event-school-\(school.id.uuidString)")
                    }
                }

                Text("\(destinationSchoolCountText) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var skippedSchoolsWarning: some View {
        if skippedSchools.count == 1, let school = skippedSchools.first {
            Text("\(school.name) has no selected recipients and will be skipped.")
                .font(.caption)
                .foregroundColor(.orange)
        } else if skippedSchools.count > 1 {
            DisclosureGroup("\(skippedSchools.count) schools have no selected recipients and will be skipped") {
                ForEach(skippedSchools) { school in
                    Text(school.name)
                        .font(.caption)
                }
            }
            .font(.caption)
            .foregroundColor(.orange)
        }
    }

    private var invitationSummary: String {
        if invitesEveryone {
            return "Everyone"
        }
        if selectedRecipientKeys.isEmpty {
            return "None selected"
        }
        return "\(selectedRecipientKeys.count) selected"
    }

    private func normalizeSchoolTarget() {
        selectedRecipientKeys = Set(selectedRecipientKeys.filter {
            destinationSchoolIds.contains($0.schoolId)
        })
    }

    private func save() {
        Task {
            if let event {
                let saved = await model.save(
                    schoolId: schoolId,
                    event: event,
                    title: title,
                    description: description,
                    startAt: startAt,
                    endAt: endAt,
                    allDay: allDay,
                    repeatRule: repeatRule,
                    invitedUserIds: []
                )
                if saved {
                    onSaved()
                    dismiss()
                }
            } else {
                let drafts = deliverableSchoolIds.map { destinationSchoolId in
                    let invitedUserIds = invitesEveryone ? [] : selectedRecipientKeys
                        .filter { $0.schoolId == destinationSchoolId }
                        .map(\.userId)
                    return EventCreationDraft(
                        schoolId: destinationSchoolId,
                        title: title.trimmed,
                        description: description.nilIfBlank,
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay,
                        repeatRule: repeatRule == "none" ? nil : repeatRule,
                        invitedUserIds: invitedUserIds,
                        idempotencyKey: "\(mutationKey)-\(destinationSchoolId.uuidString)"
                    )
                }
                let saved = await model.save(drafts: drafts)
                if saved {
                    onSaved()
                    dismiss()
                }
            }
        }
    }
}

private struct EventInviteAudiencePicker: View {
    @Environment(\.dismiss) private var dismiss

    let options: [EventMemberOption]
    let isMultiSchool: Bool
    @Binding var invitesEveryone: Bool
    @Binding var selectedRecipientKeys: Set<EventRecipientSelectionKey>

    @State private var searchText = ""

    private var filteredOptions: [EventMemberOption] {
        let sortedOptions = options.sorted { $0.sortKey < $1.sortKey }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return sortedOptions }
        return sortedOptions.filter {
            $0.member.displayName.localizedCaseInsensitiveContains(query)
                || ($0.schoolName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Audience") {
                    audienceRow(
                        title: "Everyone",
                        subtitle: isMultiSchool
                            ? "Notify everyone eligible across the selected schools."
                            : "Notify everyone eligible at this school.",
                        isSelected: invitesEveryone
                    ) {
                        invitesEveryone = true
                        selectedRecipientKeys.removeAll()
                    }

                    audienceRow(
                        title: "Specific People",
                        subtitle: "Search for and choose individual recipients.",
                        isSelected: invitesEveryone == false
                    ) {
                        invitesEveryone = false
                    }
                }

                if invitesEveryone == false {
                    Section {
                        if filteredOptions.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            ForEach(filteredOptions) { option in
                                Button {
                                    toggle(option.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.member.displayName)
                                                .foregroundColor(.primary)
                                            if isMultiSchool, let schoolName = option.schoolName {
                                                Text("\(option.member.membership.role.title) · \(schoolName)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Text(option.member.membership.role.title)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if selectedRecipientKeys.contains(option.id) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(AppConstants.Colors.primaryAction)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("People · \(selectedRecipientKeys.count) selected")
                    } footer: {
                        Text("Only the selected people will receive this event notification.")
                    }
                }
            }
            .navigationTitle("Invite People")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: isMultiSchool ? "Search by name or school" : "Search by name")
            .toolbar {
                if invitesEveryone == false {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu("Selection") {
                            Button("Select All") {
                                selectedRecipientKeys = Set(options.map(\.id))
                            }
                            Button("Clear Selection", role: .destructive) {
                                selectedRecipientKeys.removeAll()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(invitesEveryone == false && selectedRecipientKeys.isEmpty)
                }
            }
        }
    }

    private func audienceRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? AppConstants.Colors.primaryAction : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ key: EventRecipientSelectionKey) {
        if selectedRecipientKeys.contains(key) {
            selectedRecipientKeys.remove(key)
        } else {
            selectedRecipientKeys.insert(key)
        }
    }
}

#Preview {
    EventsView()
        .environmentObject(AppSessionManager())
}
