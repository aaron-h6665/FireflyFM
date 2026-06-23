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
    @State private var attendance: [ChildAttendance] = []
    @State private var activityLogs: [ChildActivityLog] = []
    @State private var progressReports: [ChildProgressReport] = []
    @State private var goals: [ChildGoal] = []
    @State private var documents: [ChildDocument] = []
    @State private var medicationInstructions: [MedicationInstruction] = []
    @State private var medicationTasks: [MedicationTask] = []
    @State private var showingMedicationComposer = false
    @State private var showingGoalComposer = false
    @State private var showingDocumentUploader = false
    @State private var acknowledgingTask: MedicationTask?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canEditSchoolRecords: Bool {
        appSession.role == .teacher || appSession.role?.canManageSchool == true
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
        .sheet(isPresented: $showingMedicationComposer) {
            MedicationInstructionComposerView(child: child) {
                Task { await loadMedication() }
            }
        }
        .sheet(isPresented: $showingGoalComposer) {
            ChildGoalComposerView(child: child) {
                Task { await loadGoals() }
            }
        }
        .sheet(isPresented: $showingDocumentUploader) {
            ChildDocumentUploaderView(child: child) {
                Task { await loadDocuments() }
            }
        }
        .sheet(item: $acknowledgingTask) { task in
            MedicationAcknowledgementView(task: task) {
                Task { await loadMedication() }
            }
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
                    .foregroundColor(.white)
                Text(child.birthdate.map { "Born \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Birthdate not set")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.58))
                Text(privacySummary)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.48))
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
            MedicalProfileEditor(child: child, profile: medicalProfile) {
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
                                    .foregroundColor(.white)
                                Text(guardian.relationship ?? "Guardian")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
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
                                .foregroundColor(.white)
                            Text([instruction.dosage, instruction.instructions].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Text("Next: \(instruction.scheduledAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                        }
                    }
                }

                Button {
                    showingMedicationComposer = true
                } label: {
                    Label("Add Medication Schedule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(AppConstants.Colors.accessibleYellow)
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
                                    .foregroundColor(.white)
                                Text(task.status.capitalized)
                                    .font(.caption)
                                    .foregroundColor(task.status == "missed" ? .red : AppConstants.Colors.accessibleYellow)
                            }
                            Spacer()
                            if canEditSchoolRecords && task.status != "acknowledged" {
                                Button("Acknowledge") {
                                    acknowledgingTask = task
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppConstants.Colors.accessibleYellow)
                            }
                        }
                    }
                }
            }

            profileSection(title: "Attendance", icon: "checkmark.circle.fill") {
                if attendance.isEmpty {
                    mutedText("No attendance records yet.")
                } else {
                    ForEach(attendance) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(attendanceText(item))
                                .font(.subheadline)
                                .foregroundColor(.white)
                            if let notes = item.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.56))
                            }
                        }
                    }
                }
            }

            profileSection(title: "Activity Logs", icon: "list.bullet.clipboard.fill") {
                if activityLogs.isEmpty {
                    mutedText("No activity logs yet.")
                } else {
                    ForEach(activityLogs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.activityType.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            if let notes = log.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            if let recordedAt = log.recordedAt {
                                Text(recordedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.42))
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
                                .foregroundColor(.white)
                            if let body = report.body, !body.isEmpty {
                                Text(body)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.62))
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
                                    .foregroundColor(.white)
                                Spacer()
                                Text(goal.status.capitalized)
                                    .font(.caption2.bold())
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(AppConstants.Colors.accessibleYellow)
                                    .clipShape(Capsule())
                            }
                            if let notes = goal.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.62))
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
                                .foregroundColor(.white)
                            Text(document.documentType.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.58))
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

            Button {
                showingDocumentUploader = true
            } label: {
                Label("Upload Document", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .tint(AppConstants.Colors.accessibleYellow)
        }
    }

    private var childInitials: String {
        "\(child.firstName.first.map(String.init) ?? "")\(child.lastName.first.map(String.init) ?? "")".uppercased()
    }

    private var privacySummary: String {
        switch appSession.role {
        case .parent: "Private child profile and school records"
        case .teacher: "Classroom child profile"
        case .schoolDirector: "School-wide child profile"
        case .hqDirector: "Franchise-level child profile"
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
            .foregroundColor(.white.opacity(0.55))
    }

    private func attendanceText(_ item: ChildAttendance) -> String {
        if let checkedInAt = item.checkedInAt {
            return "Checked in \(checkedInAt.formatted(date: .abbreviated, time: .shortened))"
        }
        if let checkedOutAt = item.checkedOutAt {
            return "Checked out \(checkedOutAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return item.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Attendance record"
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedGuardians = SchoolWorkflowService.shared.fetchChildGuardians(childId: child.id)
            async let loadedMedical = SchoolWorkflowService.shared.fetchChildMedicalProfile(childId: child.id)
            async let loadedAttendance = SchoolWorkflowService.shared.fetchChildAttendance(childId: child.id)
            async let loadedLogs = SchoolWorkflowService.shared.fetchChildActivityLogs(childId: child.id)
            async let loadedReports = SchoolWorkflowService.shared.fetchChildProgressReports(childId: child.id)
            async let loadedGoals = SchoolWorkflowService.shared.fetchChildGoals(childId: child.id)
            async let loadedDocuments = SchoolWorkflowService.shared.fetchChildDocuments(childId: child.id)
            async let loadedInstructions = SchoolWorkflowService.shared.fetchMedicationInstructions(childId: child.id)
            async let loadedTasks = SchoolWorkflowService.shared.fetchMedicationTasks(schoolId: child.schoolId, childId: child.id)

            guardians = try await loadedGuardians
            medicalProfile = try await loadedMedical
            attendance = try await loadedAttendance
            activityLogs = try await loadedLogs
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

private struct MedicalProfileEditor: View {
    let child: Child
    let profile: ChildMedicalProfile?
    var onSaved: () -> Void

    @State private var allergies = ""
    @State private var medicalNotes = ""
    @State private var medicationInstructions = ""
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

            profileField("Allergies", text: $allergies)
            profileField("Medical notes", text: $medicalNotes)
            profileField("Medication instructions", text: $medicationInstructions)
            profileField("Sleep habits", text: $sleepHabits)
            profileField("Dietary notes", text: $dietaryNotes)
            profileField("Emergency notes", text: $emergencyNotes)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red)
            }

            Button(isSaving ? "Saving" : "Save Details") { save() }
                .buttonStyle(.borderedProminent)
                .tint(AppConstants.Colors.accessibleYellow)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
        .onAppear {
            allergies = profile?.allergies ?? ""
            medicalNotes = profile?.medicalNotes ?? ""
            medicationInstructions = profile?.medicationInstructions ?? ""
            sleepHabits = profile?.sleepHabits ?? ""
            dietaryNotes = profile?.dietaryNotes ?? ""
            emergencyNotes = profile?.emergencyNotes ?? ""
        }
        .onChange(of: profile) { _, newProfile in
            allergies = newProfile?.allergies ?? ""
            medicalNotes = newProfile?.medicalNotes ?? ""
            medicationInstructions = newProfile?.medicationInstructions ?? ""
            sleepHabits = newProfile?.sleepHabits ?? ""
            dietaryNotes = newProfile?.dietaryNotes ?? ""
            emergencyNotes = newProfile?.emergencyNotes ?? ""
        }
    }

    private func profileField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.54))
            TextField(title, text: text, axis: .vertical)
                .lineLimit(2...5)
                .padding(10)
                .background(AppConstants.Colors.background.opacity(0.45))
                .cornerRadius(8)
                .foregroundColor(.white)
                .tint(AppConstants.Colors.accessibleYellow)
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
                    medicalNotes: cleaned(medicalNotes),
                    medicationInstructions: cleaned(medicationInstructions),
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
