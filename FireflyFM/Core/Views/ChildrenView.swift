//
//  ChildrenView.swift
//  FireflyFM
//

import SwiftUI

struct ChildrenView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var rosterItems: [ChildRosterItem] = []
    @State private var selectedActivityChild: Child?
    @State private var attendanceDraft: AttendanceDraft?
    @State private var editingRosterItem: ChildRosterItem?
    @State private var archivingChild: Child?
    @State private var showingAddChild = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canAddChild: Bool {
        appSession.role == .parent
    }

    private var canManageChildren: Bool {
        appSession.role?.canManageSchool == true
    }

    private var canRecordSchoolActivity: Bool {
        appSession.role == .teacher || appSession.role?.canManageSchool == true
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(descriptionText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.65))

                        if isLoading {
                            ProgressView().tint(AppConstants.Colors.accessibleYellow)
                        } else if rosterItems.isEmpty {
                            emptyPanel(emptyText)
                        } else {
                            LazyVGrid(columns: gridColumns(width: geometry.size.width), alignment: .leading, spacing: 12) {
                                ForEach(rosterItems) { item in
                                    ChildRosterCard(
                                        item: item,
                                        canRecordSchoolActivity: canRecordSchoolActivity,
                                        onCheckIn: { attendanceDraft = AttendanceDraft(child: item.child, checkingIn: true) },
                                        onCheckOut: { attendanceDraft = AttendanceDraft(child: item.child, checkingIn: false) },
                                        onRecord: { selectedActivityChild = item.child }
                                    )
                                    .contextMenu {
                                        if canManageChildren {
                                            Button {
                                                editingRosterItem = item
                                            } label: {
                                                Label("Edit Child", systemImage: "square.and.pencil")
                                            }
                                            Button(role: .destructive) {
                                                archivingChild = item.child
                                            } label: {
                                                Label("Archive Child", systemImage: "archivebox.fill")
                                            }
                                        }
                                    }
                                }
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
                .refreshable {
                    await loadRoster()
                }
            }
        }
        .navigationTitle("Children")
        .toolbar {
            if canAddChild {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddChild = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }
        }
        .sheet(item: $selectedActivityChild) { child in
            ChildActivityComposerView(child: child) {
                Task { await loadRoster() }
            }
        }
        .sheet(item: $attendanceDraft) { draft in
            AttendanceConfirmationView(draft: draft) {
                Task { await loadRoster() }
            }
        }
        .sheet(item: $editingRosterItem) { item in
            ChildEditorView(item: item) {
                Task { await loadRoster() }
            }
        }
        .sheet(isPresented: $showingAddChild) {
            AddChildView {
                Task { await loadRoster() }
            }
        }
        .confirmationDialog(
            "Archive child?",
            isPresented: Binding(
                get: { archivingChild != nil },
                set: { isPresented in
                    if !isPresented {
                        archivingChild = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let archivingChild {
                Button("Archive \(archivingChild.fullName)", role: .destructive) {
                    archive(archivingChild)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deactivates the child and preserves attendance, records, documents, and audit history.")
        }
        .task {
            await loadRoster()
        }
    }

    private var descriptionText: String {
        switch appSession.role {
        case .parent:
            "View your children's profiles, school records, attendance, medicine notes, and documents."
        case .teacher:
            "Use the roster for check-in, check-out, medicine notes, activity logs, and child records."
        case .schoolDirector:
            "Manage the school roster, child records, attendance, guardians, medicine notes, and archives."
        case .hqDirector:
            "Review children across schools with school-scoped privacy and archive controls."
        case .none:
            "Children and school records."
        }
    }

    private var emptyText: String {
        appSession.role == .parent ? "Add your child to begin the intake checklist." : "No active children are available for this school yet."
    }

    private func gridColumns(width: CGFloat) -> [GridItem] {
        let columnCount: Int
        if width >= 980 {
            columnCount = 3
        } else if width >= 660 {
            columnCount = 2
        } else {
            columnCount = 1
        }
        return Array(repeating: GridItem(.flexible(minimum: 220), spacing: 12), count: columnCount)
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
    private func loadRoster() async {
        isLoading = true
        errorMessage = nil
        do {
            if appSession.role == .hqDirector {
                rosterItems = try await SchoolWorkflowService.shared.fetchAllChildRosterForHQ()
            } else if let schoolId = appSession.activeSchool?.id {
                rosterItems = try await SchoolWorkflowService.shared.fetchChildRoster(schoolId: schoolId)
            } else {
                rosterItems = []
            }
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load children", error)
            isLoading = false
        }
    }

    private func archive(_ child: Child) {
        Task {
            do {
                try await SchoolWorkflowService.shared.archiveChild(childId: child.id, reason: "Archived from Children workspace")
                await loadRoster()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not archive child", error)
                }
            }
        }
    }
}

private struct ChildRosterCard: View {
    let item: ChildRosterItem
    let canRecordSchoolActivity: Bool
    let onCheckIn: () -> Void
    let onCheckOut: () -> Void
    let onRecord: () -> Void

    private var child: Child { item.child }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                ChildProfileView(child: child)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(AppConstants.Colors.background.opacity(0.56))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(initials)
                                .font(.headline.bold())
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(child.fullName)
                            .font(.headline)
                            .foregroundColor(.white)
                        if let birthdate = child.birthdate {
                            Text(birthdate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.52))
                        }
                    }
                    Spacer()
                    statusPill
                }
            }
            .buttonStyle(.plain)

            quickFacts

            if canRecordSchoolActivity {
                HStack(spacing: 8) {
                    Button(action: onCheckIn) {
                        Label("In", systemImage: "checkmark.circle.fill")
                    }
                    Button(action: onCheckOut) {
                        Label("Out", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    Button(action: onRecord) {
                        Label("Note", systemImage: "text.badge.plus")
                    }
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .tint(AppConstants.Colors.accessibleYellow)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private var statusPill: some View {
        Text(item.attendanceStatus)
            .font(.caption2.bold())
            .foregroundColor(item.isCheckedIn ? .black : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        if item.isCheckedIn { return .green }
        if item.todayAttendance?.checkedOutAt != nil { return .white.opacity(0.18) }
        return AppConstants.Colors.background.opacity(0.72)
    }

    private var quickFacts: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(badges, id: \.self) { badge in
                Label(badge, systemImage: badgeIcon(badge))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
    }

    private var badges: [String] {
        var values: [String] = []
        if let allergies = clean(item.medicalProfile?.allergies), allergies.lowercased() != "none" {
            values.append("Allergies: \(allergies)")
        }
        if item.pendingMedicationCount > 0 {
            values.append("\(item.pendingMedicationCount) medicine task\(item.pendingMedicationCount == 1 ? "" : "s")")
        }
        values.append("Immunization: \(clean(item.medicalProfile?.immunizationStatus) ?? "Not submitted")")
        values.append("Physical: \(clean(item.medicalProfile?.physicalStatus) ?? "Not submitted")")
        if item.submittedDocumentCount > 0 {
            values.append("\(item.submittedDocumentCount) document\(item.submittedDocumentCount == 1 ? "" : "s") in review")
        }
        return Array(values.prefix(5))
    }

    private var initials: String {
        "\(child.firstName.first.map(String.init) ?? "")\(child.lastName.first.map(String.init) ?? "")".uppercased()
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func badgeIcon(_ badge: String) -> String {
        if badge.hasPrefix("Allergies") { return "exclamationmark.triangle.fill" }
        if badge.contains("medicine") { return "pills.fill" }
        if badge.hasPrefix("Immunization") { return "cross.case.fill" }
        if badge.hasPrefix("Physical") { return "heart.text.square.fill" }
        return "doc.text.fill"
    }
}

private struct AttendanceDraft: Identifiable {
    let child: Child
    let checkingIn: Bool

    var id: String { "\(child.id.uuidString)-\(checkingIn ? "in" : "out")" }
}

private struct AttendanceConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    let draft: AttendanceDraft
    var onSaved: () -> Void

    @State private var recordedAt = Date()
    @State private var notes = ""
    @State private var confirmed = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(draft.child.fullName) {
                    DatePicker(actionTitle, selection: $recordedAt, displayedComponents: [.date, .hourAndMinute])
                    TextField("Notes", text: $notes, axis: .vertical)
                    Toggle(confirmText, isOn: $confirmed)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle(actionTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(!confirmed || isSaving)
                }
            }
        }
    }

    private var actionTitle: String {
        draft.checkingIn ? "Check In" : "Check Out"
    }

    private var confirmText: String {
        "Confirm \(draft.child.firstName) was \(draft.checkingIn ? "checked in" : "checked out") at \(recordedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.recordAttendance(
                    schoolId: draft.child.schoolId,
                    childId: draft.child.id,
                    checkingIn: draft.checkingIn,
                    recordedAt: recordedAt,
                    notes: cleaned(notes)
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save attendance", error)
                }
            }
        }
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AddChildView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    var onSaved: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var hasBirthdate = false
    @State private var birthdate = Date()
    @State private var allergies = ""
    @State private var immunizationStatus = ""
    @State private var physicalStatus = ""
    @State private var sleepHabits = ""
    @State private var dietaryNotes = ""
    @State private var emergencyNotes = ""
    @State private var medicalNotes = ""
    @State private var medicationInstructions = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Child") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                    Toggle("Add birthdate", isOn: $hasBirthdate)
                    if hasBirthdate {
                        DatePicker("Birthdate", selection: $birthdate, displayedComponents: [.date])
                    }
                }
                Section("Health and Intake") {
                    TextField("Allergies", text: $allergies, axis: .vertical)
                    TextField("Immunization status", text: $immunizationStatus, axis: .vertical)
                    TextField("Physical status", text: $physicalStatus, axis: .vertical)
                    TextField("Sleep habits", text: $sleepHabits, axis: .vertical)
                    TextField("Dietary notes", text: $dietaryNotes, axis: .vertical)
                    TextField("Emergency notes", text: $emergencyNotes, axis: .vertical)
                    TextField("Medical notes", text: $medicalNotes, axis: .vertical)
                    TextField("Medication instructions", text: $medicationInstructions, axis: .vertical)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Add Child")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
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
                let child = try await SchoolWorkflowService.shared.createChildForCurrentParent(
                    schoolId: schoolId,
                    firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    birthdate: hasBirthdate ? birthdate : nil
                )
                try await SchoolWorkflowService.shared.saveChildMedicalProfile(
                    childId: child.id,
                    allergies: cleaned(allergies),
                    immunizationStatus: cleaned(immunizationStatus),
                    physicalStatus: cleaned(physicalStatus),
                    medicalNotes: cleaned(medicalNotes),
                    medicationInstructions: cleaned(medicationInstructions),
                    sleepHabits: cleaned(sleepHabits),
                    dietaryNotes: cleaned(dietaryNotes),
                    emergencyNotes: cleaned(emergencyNotes)
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not add child", error)
                }
            }
        }
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ChildEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let item: ChildRosterItem
    var onSaved: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var hasBirthdate = false
    @State private var birthdate = Date()
    @State private var allergies = ""
    @State private var immunizationStatus = ""
    @State private var physicalStatus = ""
    @State private var sleepHabits = ""
    @State private var dietaryNotes = ""
    @State private var emergencyNotes = ""
    @State private var medicalNotes = ""
    @State private var medicationInstructions = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Child") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                    Toggle("Has birthdate", isOn: $hasBirthdate)
                    if hasBirthdate {
                        DatePicker("Birthdate", selection: $birthdate, displayedComponents: [.date])
                    }
                }
                Section("Health and Intake") {
                    TextField("Allergies", text: $allergies, axis: .vertical)
                    TextField("Immunization status", text: $immunizationStatus, axis: .vertical)
                    TextField("Physical status", text: $physicalStatus, axis: .vertical)
                    TextField("Sleep habits", text: $sleepHabits, axis: .vertical)
                    TextField("Dietary notes", text: $dietaryNotes, axis: .vertical)
                    TextField("Emergency notes", text: $emergencyNotes, axis: .vertical)
                    TextField("Medical notes", text: $medicalNotes, axis: .vertical)
                    TextField("Medication instructions", text: $medicationInstructions, axis: .vertical)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Edit Child")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear(perform: loadInitialValues)
        }
    }

    private func loadInitialValues() {
        firstName = item.child.firstName
        lastName = item.child.lastName
        if let birthdate = item.child.birthdate {
            self.birthdate = birthdate
            hasBirthdate = true
        }
        allergies = item.medicalProfile?.allergies ?? ""
        immunizationStatus = item.medicalProfile?.immunizationStatus ?? ""
        physicalStatus = item.medicalProfile?.physicalStatus ?? ""
        sleepHabits = item.medicalProfile?.sleepHabits ?? ""
        dietaryNotes = item.medicalProfile?.dietaryNotes ?? ""
        emergencyNotes = item.medicalProfile?.emergencyNotes ?? ""
        medicalNotes = item.medicalProfile?.medicalNotes ?? ""
        medicationInstructions = item.medicalProfile?.medicationInstructions ?? ""
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.updateChild(
                    childId: item.child.id,
                    firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    birthdate: hasBirthdate ? birthdate : nil
                )
                try await SchoolWorkflowService.shared.saveChildMedicalProfile(
                    childId: item.child.id,
                    allergies: cleaned(allergies),
                    immunizationStatus: cleaned(immunizationStatus),
                    physicalStatus: cleaned(physicalStatus),
                    medicalNotes: cleaned(medicalNotes),
                    medicationInstructions: cleaned(medicationInstructions),
                    sleepHabits: cleaned(sleepHabits),
                    dietaryNotes: cleaned(dietaryNotes),
                    emergencyNotes: cleaned(emergencyNotes)
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save child", error)
                }
            }
        }
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ChildActivityComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let child: Child
    var onSaved: () -> Void

    @State private var activityType = "medication"
    @State private var notes = ""
    @State private var errorMessage: String?

    private let activityTypes = [
        ("medication", "Medication"),
        ("pickup_change", "Pickup Change"),
        ("absence", "Absence"),
        ("bowel_movement", "Bowel Movement"),
        ("potty_training", "Potty Training"),
        ("meal", "Meal"),
        ("nap", "Nap"),
        ("note", "General Note")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(child.fullName) {
                    Picker("Activity", selection: $activityType) {
                        ForEach(activityTypes, id: \.0) { type in
                            Text(type.1).tag(type.0)
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Record Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        Task {
            do {
                try await SchoolWorkflowService.shared.recordChildActivity(
                    schoolId: child.schoolId,
                    childId: child.id,
                    activityType: activityType,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                )
                await MainActor.run {
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not record note", error) }
            }
        }
    }
}
