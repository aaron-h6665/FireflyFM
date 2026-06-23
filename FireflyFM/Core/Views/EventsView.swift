//
//  EventsView.swift
//  FireflyFM
//

import SwiftUI
import SDWebImageSwiftUI

struct EventsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var events: [SchoolEvent] = []
    @State private var members: [SchoolMember] = []
    @State private var profilesById: [UUID: UserProfile] = [:]
    @State private var selectedMode: EventDisplayMode = .list
    @State private var displayMonth = Date()
    @State private var selectedDate = Date()
    @State private var showingCreation = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        modePicker

                        if isLoading {
                            ProgressView().tint(AppConstants.Colors.accessibleYellow)
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
                EventCreationView(members: members) {
                    Task { await loadEvents() }
                }
            }
            .task { await loadEvents() }
        }
    }

    private var header: some View {
        HStack {
            Text("Events")
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            Spacer()

            Button {
                withAnimation(.snappy) {
                    selectedMode = selectedMode == .list ? .calendar : .list
                }
            } label: {
                Image(systemName: selectedMode == .list ? "calendar" : "list.bullet")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }

            if appSession.role?.canManageEvents == true {
                Button {
                    showingCreation = true
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("Event View", selection: $selectedMode) {
            Text("List").tag(EventDisplayMode.list)
            Text("Calendar").tag(EventDisplayMode.calendar)
        }
        .pickerStyle(.segmented)
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
                EventCardView(event: event, creator: event.createdBy.flatMap { profilesById[$0] })
            }
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
            .foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
    }

    @MainActor
    private func loadEvents() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            events = try await SchoolWorkflowService.shared.fetchEvents(schoolId: schoolId)
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
}

private enum EventDisplayMode: String, CaseIterable, Identifiable {
    case list
    case calendar

    var id: String { rawValue }
}

private struct EventMonthGroup: Identifiable {
    let month: Date
    let events: [SchoolEvent]

    var id: Date { month }

    var title: String {
        month.formatted(.dateTime.month(.wide).year())
    }
}

private struct EventCardView: View {
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
                    .foregroundColor(.white)
            }
            .frame(width: 54, height: 58)
            .background(AppConstants.Colors.background.opacity(0.45))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 7) {
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(timeText)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)

                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    ProfileMiniView(profile: creator)
                    Text(creator?.displayName ?? "School Staff")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                    if let repeatRule = event.repeatRule, repeatRule != "none" {
                        Text(repeatRule.capitalized)
                            .font(.caption2.bold())
                            .foregroundColor(.black)
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

private struct ProfileMiniView: View {
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
                            .foregroundColor(.white)
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

private struct CalendarMonthView: View {
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
                        .foregroundColor(.white)
                }

                Spacer()

                Text(displayMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button {
                    moveMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday.uppercased())
                        .font(.caption2.bold())
                        .foregroundColor(.white.opacity(0.45))
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
                    .foregroundColor(isSelected ? .black : .white)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? AppConstants.Colors.accessibleYellow : isToday ? Color.white.opacity(0.16) : Color.clear)
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

private struct EventCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let members: [SchoolMember]
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

                Section("Notifications") {
                    Toggle("Share as notification", isOn: $shareAsNotification)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Event")
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
        guard let schoolId = appSession.activeSchool?.id else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
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
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not create event", error)
                }
            }
        }
    }
}

#Preview {
    EventsView()
        .environmentObject(AppSessionManager())
}
