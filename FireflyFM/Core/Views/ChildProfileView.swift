//
//  ChildProfileView.swift
//  FireflyFM
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ChildProfileView: View {
    let child: Child

    @EnvironmentObject private var appSession: AppSessionManager

    @State private var selectedTab: ChildProfileTab = .overview
    @State private var guardians: [ChildGuardian] = []
    @State private var guardianProfiles: [UUID: UserProfile] = [:]
    @State private var medicalProfile: ChildMedicalProfile?
    @State private var attendance: [AttendanceSession] = []
    @State private var careEvents: [ChildCareEvent] = []
    @State private var progressReports: [ChildProgressReport] = []
    @State private var goals: [ChildGoal] = []
    @State private var documents: [ChildDocument] = []
    @State private var medicationInstructions: [MedicationInstruction] = []
    @State private var medicationTasks: [MedicationTask] = []
    @State private var selectedAttendanceDate = Date()
    @State private var showingGoalComposer = false
    @State private var guardianPendingRemoval: ChildGuardian?
    @State private var parentPendingDeactivation: ChildGuardian?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canEditSchoolRecords: Bool {
        appSession.role == .teacher || appSession.role?.canManageSchool == true
    }

    private var canEditChildProfile: Bool {
        appSession.role?.canManageSchool == true
    }

    private var canManageGuardians: Bool {
        appSession.role?.canManageSchool == true
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    tabPicker
                    tabContent

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            .refreshable { await load() }
        }
        .navigationTitle(child.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppConstants.Colors.card, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showingGoalComposer) {
            ChildGoalComposerView(child: child) {
                Task { await loadGoals() }
            }
        }
        .confirmationDialog(
            "Remove guardian?",
            isPresented: Binding(
                get: { guardianPendingRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        guardianPendingRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let guardianPendingRemoval {
                Button("Unlink Guardian", role: .destructive) {
                    unlinkGuardian(guardianPendingRemoval)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes this parent's access to \(child.firstName)'s records unless they are linked again.")
        }
        .confirmationDialog(
            "Deactivate parent?",
            isPresented: Binding(
                get: { parentPendingDeactivation != nil },
                set: { isPresented in
                    if !isPresented {
                        parentPendingDeactivation = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let parentPendingDeactivation {
                Button("Deactivate Parent", role: .destructive) {
                    deactivateParent(parentPendingDeactivation)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deactivates the parent's school membership and removes access to this child unless the parent is reactivated and linked again.")
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(AppConstants.Colors.card)
                .frame(width: 68, height: 68)
                .overlay(
                    Text(childInitials)
                        .font(.title3.bold())
                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(child.fullName)
                    .font(.largeTitle.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(child.birthdate.map { "Born \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Birthdate not set")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                Text(privacySummary)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.48))
            }
            Spacer()
        }
    }

    private var tabPicker: some View {
        Picker("Child Profile", selection: $selectedTab) {
            ForEach(ChildProfileTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        if isLoading {
            ProgressView()
                .tint(AppConstants.Colors.accessibleYellow)
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            switch selectedTab {
            case .overview:
                overviewContent
            case .records:
                recordsContent
            case .goals:
                goalsContent
            case .documents:
                documentsContent
            }
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            CriticalChildInfoPanel(
                profile: medicalProfile,
                documents: documents,
                pendingMedicationCount: medicationTasks.filter { $0.status != "acknowledged" }.count
            )

            MedicalProfileEditor(child: child, profile: medicalProfile, canEdit: canEditChildProfile) {
                Task { await loadMedicalProfile() }
            }

            profileSection(title: "Guardians", icon: "person.2.fill") {
                if guardians.isEmpty {
                    mutedText("No guardians listed yet.")
                } else {
                    ForEach(guardians) { guardian in
                        HStack {
                            CommunityProfileAvatar(profile: guardianProfiles[guardian.guardianId], size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(guardianProfiles[guardian.guardianId]?.displayName ?? "Guardian")
                                    .font(.subheadline.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Text(guardian.relationship ?? "Guardian")
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.5))
                            }
                            Spacer()
                            if canManageGuardians {
                                Menu {
                                    Button(role: .destructive) {
                                        guardianPendingRemoval = guardian
                                    } label: {
                                        Label("Unlink from Child", systemImage: "person.crop.circle.badge.minus")
                                    }
                                    Button(role: .destructive) {
                                        parentPendingDeactivation = guardian
                                    } label: {
                                        Label("Deactivate Parent", systemImage: "person.fill.xmark")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            }
                        }
                    }
                }
            }

            profileSection(title: "Medication Instructions", icon: "pills.fill") {
                if medicationInstructions.isEmpty {
                    mutedText("No active medication instructions.")
                } else {
                    ForEach(medicationInstructions) { instruction in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(instruction.title)
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text([instruction.dosage, instruction.instructions].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.6))
                            Text("Next: \(instruction.scheduledAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                        }
                    }
                }

                NavigationLink {
                    AssignmentsView(surface: .all)
                } label: {
                    Label("Open Medication Authorizations", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered).tint(AppConstants.Colors.accessibleYellow)
            }
        }
    }

    private var recordsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            profileSection(title: "Medication Tasks", icon: "alarm.fill") {
                if medicationTasks.isEmpty {
                    mutedText("No pending medication tasks.")
                } else {
                    ForEach(medicationTasks) { task in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.dueAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Text(task.status.capitalized)
                                    .font(.caption)
                                    .foregroundColor(task.status == "missed" ? .red : AppConstants.Colors.accessibleYellow)
                            }
                            Spacer()
                        }
                    }
                    if canEditSchoolRecords {
                        NavigationLink("Administer in Care Today") { CareTodayView() }
                            .buttonStyle(.bordered).tint(AppConstants.Colors.accessibleYellow)
                    }
                }
            }

            profileSection(title: "Attendance", icon: "checkmark.circle.fill") {
                attendanceMonthCalendar
                if selectedDayAttendance.isEmpty {
                    mutedText("No attendance records yet.")
                } else {
                    ForEach(selectedDayAttendance) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.state == .checkedOut ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.state.title).font(.subheadline.bold())
                                if let checkedIn = item.checkedInAt { Text("Checked in \(checkedIn.formatted(date: .omitted, time: .shortened))").font(.caption) }
                                if let checkedOut = item.checkedOutAt { Text("Checked out \(checkedOut.formatted(date: .omitted, time: .shortened))").font(.caption) }
                                if let notes = item.notes, !notes.isEmpty { Text(notes).font(.caption).foregroundColor(AppConstants.Colors.secondaryText) }
                            }
                        }
                    }
                }
            }

            profileSection(title: "Care Feed", icon: "list.bullet.clipboard.fill") {
                if careEvents.isEmpty {
                    mutedText("No structured care events yet.")
                } else {
                    ForEach(careEvents) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: event.eventType.symbol).foregroundColor(AppConstants.Colors.accessibleYellow).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.eventType.title).font(.subheadline.bold())
                                    Spacer(); Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2)
                                }
                                ForEach(event.details.keys.sorted(), id: \.self) { key in
                                    if let value = event.details[key]?.stringValue, !value.isEmpty {
                                        Text(value).font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
                                    }
                                }
                                if !event.developmentalDomains.isEmpty {
                                    Text(event.developmentalDomains.compactMap { ChildDevelopmentalDomain(rawValue: $0)?.title }.joined(separator: " • "))
                                        .font(.caption2).foregroundColor(AppConstants.Colors.primaryAction)
                                }
                                if event.reportHighlight {
                                    Label("Progress Highlight", systemImage: "star.circle.fill")
                                        .font(.caption2.bold()).foregroundColor(AppConstants.Colors.primaryAction)
                                }
                                if event.visibility == "staff_only" { Label("Staff Only", systemImage: "lock.fill").font(.caption2).foregroundColor(.orange) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var goalsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            profileSection(title: "Progress Reports", icon: "doc.text.magnifyingglass") {
                if progressReports.isEmpty {
                    mutedText("No progress reports yet.")
                } else {
                    ForEach(progressReports) { report in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(report.title)
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            if let body = report.body, !body.isEmpty {
                                Text(body)
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                            }
                        }
                    }
                }
            }

            profileSection(title: "Goals", icon: "target") {
                if goals.isEmpty {
                    mutedText("No goals yet.")
                } else {
                    ForEach(goals) { goal in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(goal.title)
                                    .font(.subheadline.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Spacer()
                                Text(goal.status.capitalized)
                                    .font(.caption2.bold())
                                    .foregroundColor(AppConstants.Colors.brandNavy)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(AppConstants.Colors.accessibleYellow)
                                    .clipShape(Capsule())
                            }
                            if let notes = goal.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                            }
                        }
                    }
                }

                if canEditSchoolRecords {
                    Button {
                        showingGoalComposer = true
                    } label: {
                        Label("Add Goal", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppConstants.Colors.accessibleYellow)
                }
            }
        }
    }

    private var documentsContent: some View {
        profileSection(title: "Documents", icon: "folder.fill") {
            if documents.isEmpty {
                mutedText("No child documents uploaded yet.")
            } else {
                ForEach(documents) { document in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.title)
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text(document.documentType.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                            Text(document.verificationStatus.capitalized)
                                .font(.caption2.bold())
                                .foregroundColor(document.verificationStatus == "verified" ? .green : document.verificationStatus == "flagged" ? .red : .orange)
                        }
                        Spacer()
                        if document.filePath != nil {
                            Button("Open") {
                                openFile(path: document.filePath)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppConstants.Colors.accessibleYellow)
                        }
                    }
                }
            }

            NavigationLink {
                AssignmentsView(surface: .all)
            } label: {
                Label("Open Child Forms", systemImage: "checklist.checked")
            }
            .buttonStyle(.bordered).tint(AppConstants.Colors.accessibleYellow)
        }
    }

    private var childInitials: String {
        "\(child.firstName.first.map(String.init) ?? "")\(child.lastName.first.map(String.init) ?? "")".uppercased()
    }

    private var selectedDayAttendance: [AttendanceSession] {
        attendance.filter { Calendar.current.isDate($0.attendanceDate, inSameDayAs: selectedAttendanceDate) }
    }

    private var attendanceMonthDays: [Date] {
        let start = Calendar.current.dateInterval(of: .month, for: selectedAttendanceDate)?.start ?? selectedAttendanceDate
        let count = Calendar.current.range(of: .day, in: .month, for: start)?.count ?? 30
        return (0..<count).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var attendanceMonthCalendar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shiftAttendanceMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer(); Text(selectedAttendanceDate.formatted(.dateTime.month(.wide).year())).font(.subheadline.bold()); Spacer()
                Button { shiftAttendanceMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 7) {
                ForEach(attendanceMonthDays, id: \.self) { day in
                    Button { selectedAttendanceDate = day } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.day())).font(.caption2)
                            Circle().fill(attendanceColor(on: day)).frame(width: 7, height: 7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(Calendar.current.isDate(day, inSameDayAs: selectedAttendanceDate) ? AppConstants.Colors.background : .clear)
                        .cornerRadius(7)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func shiftAttendanceMonth(_ value: Int) {
        selectedAttendanceDate = Calendar.current.date(byAdding: .month, value: value, to: selectedAttendanceDate) ?? selectedAttendanceDate
    }

    private func attendanceColor(on day: Date) -> Color {
        guard let record = attendance.first(where: { Calendar.current.isDate($0.attendanceDate, inSameDayAs: day) }) else { return .clear }
        switch record.state {
        case .expected: return .blue
        case .present: return .green
        case .checkedOut: return .gray
        case .absent: return .orange
        case .needsAttention: return .red
        }
    }

    private var privacySummary: String {
        switch appSession.role {
        case .parent: "Private child profile and school records"
        case .teacher: "School child profile"
        case .schoolDirector: "School-wide child profile"
        case .hqDirector: "HQ-wide child profile"
        case .none: "Child profile"
        }
    }

    private func profileSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func mutedText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedGuardians = SchoolWorkflowService.shared.fetchChildGuardians(childId: child.id)
            async let loadedMedical = SchoolWorkflowService.shared.fetchChildMedicalProfile(childId: child.id)
            let historyStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
            async let loadedAttendance = SchoolOperationsService.shared.fetchAttendance(schoolId: child.schoolId, startDate: historyStart, endDate: Date())
            async let loadedCareEvents = SchoolOperationsService.shared.fetchCareEvents(schoolId: child.schoolId, start: historyStart, end: Date().addingTimeInterval(86_400), childId: child.id)
            async let loadedReports = SchoolWorkflowService.shared.fetchChildProgressReports(childId: child.id)
            async let loadedGoals = SchoolWorkflowService.shared.fetchChildGoals(childId: child.id)
            async let loadedDocuments = SchoolWorkflowService.shared.fetchChildDocuments(childId: child.id)
            async let loadedInstructions = SchoolWorkflowService.shared.fetchMedicationInstructions(childId: child.id)
            async let loadedTasks = SchoolWorkflowService.shared.fetchMedicationTasks(schoolId: child.schoolId, childId: child.id)

            guardians = try await loadedGuardians
            medicalProfile = try await loadedMedical
            attendance = try await loadedAttendance
            attendance = attendance.filter { $0.childId == child.id }
            careEvents = try await loadedCareEvents
            progressReports = try await loadedReports
            goals = try await loadedGoals
            documents = try await loadedDocuments
            medicationInstructions = try await loadedInstructions
            medicationTasks = try await loadedTasks
            guardianProfiles = try await ProfileService.shared.fetchProfiles(ids: guardians.map(\.guardianId))
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load child profile", error)
            isLoading = false
        }
    }

    @MainActor
    private func loadMedicalProfile() async {
        do {
            medicalProfile = try await SchoolWorkflowService.shared.fetchChildMedicalProfile(childId: child.id)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not refresh medical profile", error)
        }
    }

    @MainActor
    private func loadGoals() async {
        do {
            goals = try await SchoolWorkflowService.shared.fetchChildGoals(childId: child.id)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not refresh goals", error)
        }
    }

    @MainActor
    private func loadDocuments() async {
        do {
            documents = try await SchoolWorkflowService.shared.fetchChildDocuments(childId: child.id)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not refresh documents", error)
        }
    }

    @MainActor
    private func loadMedication() async {
        do {
            async let loadedInstructions = SchoolWorkflowService.shared.fetchMedicationInstructions(childId: child.id)
            async let loadedTasks = SchoolWorkflowService.shared.fetchMedicationTasks(schoolId: child.schoolId, childId: child.id)
            medicationInstructions = try await loadedInstructions
            medicationTasks = try await loadedTasks
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not refresh medication records", error)
        }
    }

    private func openFile(path: String?) {
        guard let path else { return }
        Task {
            do {
                let url = try await SchoolService.shared.signedPrivateFileURL(path: path)
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not open file", error)
                }
            }
        }
    }

    private func unlinkGuardian(_ guardian: ChildGuardian) {
        Task {
            do {
                try await SchoolWorkflowService.shared.unlinkChildGuardian(childId: child.id, guardianId: guardian.guardianId)
                await load()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not unlink guardian", error)
                }
            }
        }
    }

    private func deactivateParent(_ guardian: ChildGuardian) {
        Task {
            do {
                try await SchoolWorkflowService.shared.deactivateSchoolMember(schoolId: child.schoolId, userId: guardian.guardianId)
                try await SchoolWorkflowService.shared.unlinkChildGuardian(childId: child.id, guardianId: guardian.guardianId)
                await load()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not deactivate parent", error)
                }
            }
        }
    }
}

private enum ChildProfileTab: String, CaseIterable, Identifiable {
    case overview
    case records
    case goals
    case documents

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .records: "Records"
        case .goals: "Goals"
        case .documents: "Docs"
        }
    }
}

private enum AttendanceRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }
}

private struct CriticalChildInfoPanel: View {
    let profile: ChildMedicalProfile?
    let documents: [ChildDocument]
    let pendingMedicationCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Important Information", systemImage: "staroflife.fill")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                infoTile("Allergies", value: clean(profile?.allergies) ?? "None listed", icon: "exclamationmark.triangle.fill")
                infoTile("Immunization", value: clean(profile?.immunizationStatus) ?? "Not submitted", icon: "cross.case.fill")
                infoTile("Physical", value: clean(profile?.physicalStatus) ?? "Not submitted", icon: "heart.text.square.fill")
                infoTile("Sleep", value: clean(profile?.sleepHabits) ?? "Not listed", icon: "moon.fill")
                infoTile("Dietary", value: clean(profile?.dietaryNotes) ?? "Not listed", icon: "fork.knife")
                infoTile("Emergency", value: clean(profile?.emergencyNotes) ?? "Not listed", icon: "phone.fill")
            }

            HStack(spacing: 10) {
                Label("\(pendingMedicationCount) pending medicine", systemImage: "pills.fill")
                Label("\(verifiedDocuments) verified docs", systemImage: "doc.text.fill")
            }
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private var verifiedDocuments: Int {
        documents.filter { $0.verificationStatus == "verified" }.count
    }

    private func infoTile(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(AppConstants.Colors.background.opacity(0.38))
        .cornerRadius(8)
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct MedicalProfileEditor: View {
    let child: Child
    let profile: ChildMedicalProfile?
    let canEdit: Bool
    var onSaved: () -> Void

    @State private var allergies = ""
    @State private var immunizationStatus = ""
    @State private var physicalStatus = ""
    @State private var medicalNotes = ""
    @State private var sleepHabits = ""
    @State private var dietaryNotes = ""
    @State private var emergencyNotes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Medical and Emergency Details", systemImage: "heart.text.square.fill")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            if canEdit {
                profileField("Allergies", text: $allergies)
                profileField("Immunization status", text: $immunizationStatus)
                profileField("Physical status", text: $physicalStatus)
                profileField("Medical notes", text: $medicalNotes)
                profileField("Sleep habits", text: $sleepHabits)
                profileField("Dietary notes", text: $dietaryNotes)
                profileField("Emergency notes", text: $emergencyNotes)
            } else {
                readOnlyField("Allergies", value: allergies)
                readOnlyField("Immunization status", value: immunizationStatus)
                readOnlyField("Physical status", value: physicalStatus)
                readOnlyField("Medical notes", value: medicalNotes)
                readOnlyField("Medication instructions", value: "Managed through approved medication authorizations")
                readOnlyField("Sleep habits", value: sleepHabits)
                readOnlyField("Dietary notes", value: dietaryNotes)
                readOnlyField("Emergency notes", value: emergencyNotes)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red)
            }

            if canEdit {
                Button(isSaving ? "Saving" : "Save Details") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppConstants.Colors.accessibleYellow)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
        .onAppear {
            allergies = profile?.allergies ?? ""
            immunizationStatus = profile?.immunizationStatus ?? ""
            physicalStatus = profile?.physicalStatus ?? ""
            medicalNotes = profile?.medicalNotes ?? ""
            sleepHabits = profile?.sleepHabits ?? ""
            dietaryNotes = profile?.dietaryNotes ?? ""
            emergencyNotes = profile?.emergencyNotes ?? ""
        }
        .onChange(of: profile) { _, newProfile in
            allergies = newProfile?.allergies ?? ""
            immunizationStatus = newProfile?.immunizationStatus ?? ""
            physicalStatus = newProfile?.physicalStatus ?? ""
            medicalNotes = newProfile?.medicalNotes ?? ""
            sleepHabits = newProfile?.sleepHabits ?? ""
            dietaryNotes = newProfile?.dietaryNotes ?? ""
            emergencyNotes = newProfile?.emergencyNotes ?? ""
        }
    }

    private func profileField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.54))
            TextField(title, text: text, axis: .vertical)
                .lineLimit(2...5)
                .padding(10)
                .background(AppConstants.Colors.background.opacity(0.45))
                .cornerRadius(8)
                .foregroundColor(AppConstants.Colors.primaryText)
                .tint(AppConstants.Colors.accessibleYellow)
        }
    }

    private func readOnlyField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.54))
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not listed" : value)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppConstants.Colors.background.opacity(0.28))
                .cornerRadius(8)
        }
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.saveChildMedicalProfile(
                    childId: child.id,
                    allergies: cleaned(allergies),
                    immunizationStatus: cleaned(immunizationStatus),
                    physicalStatus: cleaned(physicalStatus),
                    medicalNotes: cleaned(medicalNotes),
                    medicationInstructions: nil,
                    sleepHabits: cleaned(sleepHabits),
                    dietaryNotes: cleaned(dietaryNotes),
                    emergencyNotes: cleaned(emergencyNotes)
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save medical details", error)
                }
            }
        }
    }
}

private struct MedicationInstructionComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let child: Child
    var onSaved: () -> Void

    @State private var title = ""
    @State private var dosage = ""
    @State private var instructions = ""
    @State private var scheduledAt = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Medication name", text: $title)
                    TextField("Dosage", text: $dosage)
                    TextField("Instructions", text: $instructions, axis: .vertical)
                    DatePicker("Scheduled time", selection: $scheduledAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Safety") {
                    Text("The teacher must acknowledge the dosage and time in-app. If a task is not acknowledged within 15 minutes, the backend creates an escalation for the school director.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Medication Schedule")
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
                try await SchoolWorkflowService.shared.createMedicationInstruction(
                    schoolId: child.schoolId,
                    childId: child.id,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : dosage,
                    instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : instructions,
                    scheduledAt: scheduledAt
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save medication schedule", error)
                }
            }
        }
    }
}

private struct MedicationAcknowledgementView: View {
    @Environment(\.dismiss) private var dismiss

    let task: MedicationTask
    var onSaved: () -> Void

    @State private var dosageGiven = ""
    @State private var notes = ""
    @State private var confirmed = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Double Acknowledge") {
                    Text("Confirm the medication was administered at the recorded time and dosage.")
                    TextField("Dosage given", text: $dosageGiven)
                    TextField("Notes", text: $notes, axis: .vertical)
                    Toggle("I confirm this dosage was given", isOn: $confirmed)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Acknowledge Medication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Confirm") { save() }
                        .disabled(!confirmed || dosageGiven.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.acknowledgeMedicationTask(
                    taskId: task.id,
                    dosageGiven: dosageGiven.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not acknowledge medication", error)
                }
            }
        }
    }
}

private struct ChildGoalComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let child: Child
    var onSaved: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Goal")
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
                try await SchoolWorkflowService.shared.createChildGoal(
                    schoolId: child.schoolId,
                    childId: child.id,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save goal", error)
                }
            }
        }
    }
}

private struct ChildDocumentUploaderView: View {
    @Environment(\.dismiss) private var dismiss

    let child: Child
    var onSaved: () -> Void

    @State private var title = ""
    @State private var documentType = "physical"
    @State private var fileURL: URL?
    @State private var showingImporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $documentType) {
                        Text("Physical").tag("physical")
                        Text("Immunization").tag("immunization")
                        Text("Emergency Contact").tag("emergency_contact")
                        Text("Progress Report").tag("progress_report")
                        Text("Other").tag("other")
                    }
                    Button(fileURL?.lastPathComponent ?? "Choose file") {
                        showingImporter = true
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Upload Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Uploading" : "Upload") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fileURL == nil || isSaving)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                fileURL = try? result.get().first
            }
        }
    }

    private func save() {
        guard let fileURL else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.uploadChildDocument(
                    schoolId: child.schoolId,
                    childId: child.id,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    documentType: documentType,
                    fileURL: fileURL
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not upload document", error)
                }
            }
        }
    }
}
