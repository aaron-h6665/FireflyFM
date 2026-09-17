import SwiftUI

struct AttendanceView: View {
    let focusSessionId: UUID?
    private let navigationTitle: String
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var model = AttendanceModel()
    @State private var searchText = ""
    @State private var statusFilter: AttendanceState?
    @State private var historyChild: Child?
    @State private var selectedChildIds: Set<UUID> = []
    @State private var selectedSchoolId: UUID?
    @State private var confirmingAbsentCheckIn = false

    init(focusSessionId: UUID? = nil, navigationTitle: String = "Attendance") {
        self.focusSessionId = focusSessionId
        self.navigationTitle = navigationTitle
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var accessPolicy: AttendanceAccessPolicy {
        AttendanceAccessPolicy(context: appSession.accessContext(selectedSchoolId: selectedSchoolId))
    }
    private var latestTodayByChild: [UUID: AttendanceSession] {
        Dictionary(grouping: model.sessions.filter { Calendar.current.isDateInToday($0.attendanceDate) }, by: \.childId)
            .compactMapValues { $0.sorted { ($0.checkedInAt ?? $0.createdAt) > ($1.checkedInAt ?? $1.createdAt) }.first }
    }
    private var filteredChildren: [Child] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.children.filter { child in
            (query.isEmpty || child.fullName.localizedCaseInsensitiveContains(query))
                && (selectedSchoolId == nil || child.schoolId == selectedSchoolId)
                && (statusFilter == nil || displayState(for: child) == statusFilter)
        }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                searchAndFilters
                if attendanceExceptions.isEmpty == false { exceptionBanner }
                if model.phase.isLoading && model.children.isEmpty {
                    Spacer(); ProgressView().tint(AppConstants.Colors.accessibleYellow); Spacer()
                } else if filteredChildren.isEmpty {
                    Spacer(); ContentUnavailableView("No attendance results", systemImage: "calendar.badge.clock"); Spacer()
                } else if accessPolicy.hasCrossSchoolScope {
                    hqAttendanceList
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                            spacing: 16
                        ) {
                            ForEach(filteredChildren) { child in attendanceGridCell(child) }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, selectedChildIds.isEmpty ? 16 : 104)
                    }
                    .refreshable { await load() }
                }
                if let errorMessage = model.errorMessage { Text(errorMessage).font(.caption).foregroundColor(.red).padding(.horizontal) }
            }
        }
        .navigationTitle(navigationTitle)
        .safeAreaInset(edge: .bottom) {
            if accessPolicy.canRecord, selectedChildIds.isEmpty == false {
                batchActionBar
            }
        }
        .sheet(item: $historyChild) { child in
            NavigationStack {
                AttendanceHistoryView(
                    child: child,
                    sessions: model.sessions.filter { $0.childId == child.id },
                    saveCorrection: model.correct
                ) {
                    Task { await load() }
                }
            }
        }
        .task(id: appSession.activeMembershipId) { await load() }
        .confirmationDialog(
            "Check in absent children?",
            isPresented: $confirmingAbsentCheckIn,
            titleVisibility: .visible
        ) {
            Button("Check In") { performBatch(action: .checkIn) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This keeps the absence record in history and starts a new attendance session now.")
        }
    }

    private var searchAndFilters: some View {
        VStack(spacing: 10) {
            FireflySearchField(placeholder: "Search the school roster", text: $searchText)
            if accessPolicy.hasCrossSchoolScope {
                Menu {
                    Button("All Schools") { selectedSchoolId = nil }
                    ForEach(model.schools) { school in
                        Button(school.name) { selectedSchoolId = school.id }
                    }
                } label: {
                    HStack {
                        Label(selectedSchoolId.map { schoolName($0) } ?? "All Schools", systemImage: "building.2.fill")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.subheadline.bold())
                    .padding(12)
                    .background(AppConstants.Colors.card)
                    .cornerRadius(10)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterButton("All", state: nil)
                    ForEach(AttendanceState.allCases) { state in filterButton(attendanceLabel(state), state: state) }
                }
            }
        }
        .padding(.horizontal)
    }

    private func attendanceGridCell(_ child: Child) -> some View {
        let state = displayState(for: child)
        let isSelected = selectedChildIds.contains(child.id)
        let isCompatible = selectedChildIds.isEmpty || selectionCohort(for: child) == activeSelectionCohort

        return VStack(spacing: 7) {
            Button {
                toggleSelection(child)
            } label: {
                Circle()
                    .fill(isSelected ? AppConstants.Colors.wingMist : stateColor(state).opacity(0.14))
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.title2.bold())
                                .foregroundColor(AppConstants.Colors.brandNavy)
                        } else {
                            Text(InitialsFormatter.initials(for: child.fullName))
                                .font(.headline.bold())
                                .foregroundColor(isCompatible ? stateColor(state) : AppConstants.Colors.secondaryText)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .opacity(isCompatible ? 1 : 0.42)
            }
            .buttonStyle(.plain)
            .disabled(isCompatible == false)
            .accessibilityLabel("\(child.fullName), \(attendanceLabel(state))")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            Text(child.firstName)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
                .lineLimit(1)
            Text(attendanceLabel(state))
                .font(.caption2)
                .foregroundColor(stateColor(state))
                .lineLimit(1)
            Button { historyChild = child } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
            .accessibilityLabel("View \(child.firstName)'s attendance history")
        }
        .frame(maxWidth: .infinity)
    }

    private var batchActionBar: some View {
        VStack(spacing: 9) {
            HStack {
                Text("\(selectedChildIds.count) selected")
                    .font(.subheadline.bold())
                Spacer()
                Button("Clear") { selectedChildIds.removeAll() }
                    .font(.caption.bold())
            }
            HStack(spacing: 10) {
                switch activeSelectionCohort {
                case .notCheckedIn:
                    batchButton("Check In", symbol: "arrow.right.circle.fill", action: .checkIn)
                    batchButton("Mark Absent", symbol: "person.crop.circle.badge.xmark", action: .absent)
                case .present:
                    batchButton("Check Out", symbol: "arrow.left.circle.fill", action: .checkOut)
                case .checkedOut:
                    batchButton("Check In Again", symbol: "arrow.uturn.right.circle.fill", action: .checkIn)
                case .absent:
                    Button {
                        confirmingAbsentCheckIn = true
                    } label: {
                        Label("Check In", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppConstants.Colors.primaryAction)
                    .foregroundColor(AppConstants.Colors.primaryActionText)
                case .needsAttention, .none:
                    Text("Open History to correct this record.")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func batchButton(_ title: String, symbol: String, action: AttendanceAction) -> some View {
        Button { performBatch(action: action) } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppConstants.Colors.primaryAction)
        .foregroundColor(AppConstants.Colors.primaryActionText)
        .disabled(model.isRecordingBatch)
    }

    private var activeSelectionCohort: AttendanceSelectionCohort? {
        guard let firstId = selectedChildIds.first,
              let child = model.children.first(where: { $0.id == firstId }) else { return nil }
        return selectionCohort(for: child)
    }

    private func selectionCohort(for child: Child) -> AttendanceSelectionCohort {
        switch displayState(for: child) {
        case .expected: .notCheckedIn
        case .present: .present
        case .checkedOut: .checkedOut
        case .absent: .absent
        case .needsAttention: .needsAttention
        }
    }

    private func toggleSelection(_ child: Child) {
        if selectedChildIds.contains(child.id) {
            selectedChildIds.remove(child.id)
            return
        }
        guard selectedChildIds.isEmpty || selectionCohort(for: child) == activeSelectionCohort else {
            model.showError("Clear the current selection before choosing children with a different attendance state.")
            return
        }
        selectedChildIds.insert(child.id)
    }

    private func performBatch(action: AttendanceAction) {
        let childIds = Array(selectedChildIds)
        guard childIds.isEmpty == false else { return }
        Task {
            if let results = await model.recordBatch(childIds: childIds, action: action) {
                let failures = results.filter { $0.success == false }
                selectedChildIds.removeAll()
                if failures.isEmpty == false {
                    model.showError(failures.count == 1
                        ? (failures[0].errorMessage ?? "One attendance update could not be saved.")
                        : "\(failures.count) attendance updates could not be saved. No records were silently skipped.")
                }
            }
        }
    }

    private func attendanceLabel(_ state: AttendanceState) -> String {
        state == .expected ? "Not checked in" : state.title
    }

    private func stateColor(_ state: AttendanceState) -> Color {
        switch state {
        case .expected: .blue
        case .present: .green
        case .checkedOut: .gray
        case .absent: .orange
        case .needsAttention: .red
        }
    }

    private func filterButton(_ title: String, state: AttendanceState?) -> some View {
        Button(title) { statusFilter = state }
            .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
            .background(statusFilter == state ? AppConstants.Colors.primaryAction : AppConstants.Colors.card)
            .foregroundColor(statusFilter == state ? AppConstants.Colors.primaryActionText : AppConstants.Colors.primaryText)
            .clipShape(Capsule())
    }

    private var exceptionBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text("\(attendanceExceptions.count) attendance record\(attendanceExceptions.count == 1 ? "" : "s") need review")
                .font(.subheadline.bold())
            Spacer()
        }
        .padding().background(Color.orange.opacity(0.12)).cornerRadius(8).padding(.horizontal)
    }

    private var hqAttendanceList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredChildren.enumerated()), id: \.element.id) { index, child in
                    hqAttendanceRow(child)
                    if index < filteredChildren.count - 1 {
                        Divider()
                            .overlay(AppConstants.Colors.separator)
                            .padding(.leading, 62)
                    }
                }
            }
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                    .stroke(AppConstants.Colors.separator.opacity(0.65), lineWidth: 1)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .refreshable { await load() }
    }

    private func hqAttendanceRow(_ child: Child) -> some View {
        let session = latestTodayByChild[child.id]
        let state = displayState(for: child)
        return HStack(spacing: 12) {
            Circle()
                .fill(stateColor(state).opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(InitialsFormatter.initials(for: child.fullName))
                        .font(.caption.bold())
                        .foregroundColor(stateColor(state))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(child.fullName)
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                HStack(spacing: 6) {
                    Text(schoolName(child.schoolId))
                    if let time = session?.checkedInAt {
                        Text("•")
                        Text(time.formatted(date: .omitted, time: .shortened))
                    }
                }
                .font(.caption)
                .foregroundColor(AppConstants.Colors.secondaryText)
            }
            Spacer(minLength: 4)
            AttendanceStatePill(state: state)
            Button { historyChild = child } label: {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundColor(AppConstants.Colors.primaryAction)
                    .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
            }
            .accessibilityLabel("View \(child.firstName)'s attendance history")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
    }

    private func displayState(for child: Child) -> AttendanceState {
        latestTodayByChild[child.id]?.state ?? .expected
    }

    private var attendanceExceptions: [AttendanceSession] {
        let open = model.sessions.filter { $0.checkedInAt != nil && $0.checkedOutAt == nil }
        let overlappingIds = Set(Dictionary(grouping: open, by: \.childId).filter { $0.value.count > 1 }.keys)
        return model.sessions.filter { $0.state == .needsAttention || overlappingIds.contains($0.childId) }
    }

    private func schoolName(_ id: UUID) -> String {
        model.schools.first(where: { $0.id == id })?.name ?? appSession.activeSchool?.name ?? "School"
    }

    @MainActor private func load() async {
        let monthStart = Calendar.current.date(byAdding: .day, value: -35, to: today) ?? today
        await model.load(scope: AttendanceScope(
            schoolId: appSession.activeSchool?.id,
            includesAllSchools: accessPolicy.hasCrossSchoolScope,
            startDate: monthStart,
            endDate: today
        ))
        if let focusSessionId,
           let session = model.sessions.first(where: { $0.id == focusSessionId }),
           let child = model.children.first(where: { $0.id == session.childId }) {
            historyChild = child
        }
    }
}

private enum AttendanceSelectionCohort {
    case notCheckedIn
    case present
    case checkedOut
    case absent
    case needsAttention
}

private struct AttendanceStatePill: View {
    let state: AttendanceState
    var body: some View {
        Text(state.title).font(.caption2.bold()).padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.18)).foregroundColor(color).clipShape(Capsule())
    }
    private var color: Color {
        switch state {
        case .expected: .blue
        case .present: .green
        case .checkedOut: .gray
        case .absent: .orange
        case .needsAttention: .red
        }
    }
}

private struct AttendanceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    private var accessPolicy: AttendanceAccessPolicy {
        AttendanceAccessPolicy(context: appSession.accessContext(selectedSchoolId: child.schoolId))
    }
    let child: Child
    let sessions: [AttendanceSession]
    let saveCorrection: (AttendanceCorrection) async throws -> Void
    var onCorrected: () -> Void
    @State private var selectedDate = Date()
    @State private var correctingSession: AttendanceSession?

    private var days: [Date] {
        let start = Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        return (0..<Calendar.current.range(of: .day, in: .month, for: start)!.count).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: start)
        }
    }
    private var selectedSessions: [AttendanceSession] {
        sessions.filter { Calendar.current.isDate($0.attendanceDate, inSameDayAs: selectedDate) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer(); Text(selectedDate.formatted(.dateTime.month(.wide).year())).font(.headline); Spacer()
                    Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                    ForEach(days, id: \.self) { day in
                        Button { selectedDate = day } label: {
                            VStack(spacing: 5) {
                                Text(day.formatted(.dateTime.day())).font(.caption)
                                Circle().fill(statusColor(day)).frame(width: 8, height: 8)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? AppConstants.Colors.card : .clear)
                            .cornerRadius(8)
                        }.buttonStyle(.plain)
                    }
                }
                Text(selectedDate.formatted(date: .complete, time: .omitted)).font(.headline)
                if selectedSessions.isEmpty { Text("No attendance record.").foregroundColor(AppConstants.Colors.secondaryText) }
                ForEach(selectedSessions) { session in
                    HStack(alignment: .top, spacing: 12) {
                        AttendanceStatePill(state: session.state)
                        VStack(alignment: .leading) {
                            if let time = session.checkedInAt {
                                Text("Checked in \(time.formatted(date: .omitted, time: .shortened))")
                                attendanceSource(
                                    method: session.checkedInMethod,
                                    actorName: session.checkedInActorName,
                                    actorRole: session.checkedInActorRole
                                )
                            }
                            if let time = session.checkedOutAt {
                                Text("Checked out \(time.formatted(date: .omitted, time: .shortened))")
                                attendanceSource(
                                    method: session.checkedOutMethod,
                                    actorName: session.checkedOutActorName,
                                    actorRole: session.checkedOutActorRole
                                )
                            }
                            if let notes = session.notes { Text(notes).font(.caption).foregroundColor(AppConstants.Colors.secondaryText) }
                        }
                        Spacer()
                        if accessPolicy.canCorrect {
                            Button("Correct") { correctingSession = session }.font(.caption.bold()).buttonStyle(.bordered)
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(AppConstants.Colors.card).cornerRadius(8)
                }
            }.padding()
        }
        .background(AppConstants.Colors.background).navigationTitle(child.fullName)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $correctingSession) { session in
            AttendanceCorrectionView(session: session, saveCorrection: saveCorrection) {
                onCorrected()
                correctingSession = nil
            }
        }
    }

    private func moveMonth(_ value: Int) { selectedDate = Calendar.current.date(byAdding: .month, value: value, to: selectedDate) ?? selectedDate }
    @ViewBuilder
    private func attendanceSource(method: String?, actorName: String?, actorRole: String?) -> some View {
        if let method {
            let source = method == "guardian_qr" ? "Parent QR" : method == "staff_manual" ? "Staff manual" : "System"
            let actor = actorName ?? actorRole?.replacingOccurrences(of: "_", with: " ").capitalized
            Text([source, actor].compactMap { $0 }.joined(separator: " • "))
                .font(.caption2)
                .foregroundColor(AppConstants.Colors.secondaryText)
        }
    }
    private func statusColor(_ day: Date) -> Color {
        guard let session = sessions.first(where: { Calendar.current.isDate($0.attendanceDate, inSameDayAs: day) }) else { return .clear }
        switch session.state { case .present: return .green; case .checkedOut: return .gray; case .absent: return .orange; case .needsAttention: return .red; case .expected: return .blue }
    }
}

private struct AttendanceCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    let session: AttendanceSession
    let saveCorrection: (AttendanceCorrection) async throws -> Void
    var onSaved: () -> Void
    @State private var state: AttendanceState
    @State private var hasCheckIn: Bool
    @State private var checkedInAt: Date
    @State private var hasCheckOut: Bool
    @State private var checkedOutAt: Date
    @State private var notes: String
    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        session: AttendanceSession,
        saveCorrection: @escaping (AttendanceCorrection) async throws -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.session = session
        self.saveCorrection = saveCorrection
        self.onSaved = onSaved
        _state = State(initialValue: session.state)
        _hasCheckIn = State(initialValue: session.checkedInAt != nil)
        _checkedInAt = State(initialValue: session.checkedInAt ?? session.attendanceDate)
        _hasCheckOut = State(initialValue: session.checkedOutAt != nil)
        _checkedOutAt = State(initialValue: session.checkedOutAt ?? session.checkedInAt ?? session.attendanceDate)
        _notes = State(initialValue: session.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Corrected record") {
                    Picker("Status", selection: $state) { ForEach(AttendanceState.allCases) { Text($0.title).tag($0) } }
                    Toggle("Has check-in", isOn: $hasCheckIn)
                    if hasCheckIn { DatePicker("Check-in", selection: $checkedInAt) }
                    Toggle("Has checkout", isOn: $hasCheckOut)
                    if hasCheckOut { DatePicker("Checkout", selection: $checkedOutAt) }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section("Audit reason") {
                    TextField("Why is this correction needed?", text: $reason, axis: .vertical)
                    Text("The prior values remain in correction history.").font(.caption).foregroundColor(.secondary)
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .onChange(of: state) { _, newState in
                if newState == .absent {
                    hasCheckIn = false
                    hasCheckOut = false
                }
            }
            .navigationTitle("Correct Attendance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || (hasCheckOut && !hasCheckIn) || (hasCheckOut && checkedOutAt < checkedInAt))
                }
            }
        }
    }

    private func save() {
        isSaving = true; errorMessage = nil
        Task {
            do {
                try await saveCorrection(AttendanceCorrection(
                    sessionId: session.id,
                    checkedInAt: hasCheckIn ? checkedInAt : nil,
                    checkedOutAt: hasCheckOut ? checkedOutAt : nil,
                    state: state,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                await MainActor.run { isSaving = false; onSaved(); dismiss() }
            } catch {
                await MainActor.run { isSaving = false; errorMessage = AppErrorMessage.school("Could not correct attendance", error) }
            }
        }
    }
}
