//
//  ChildrenView.swift
//  FireflyFM
//

import SwiftUI

struct ChildrenView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var children: [Child] = []
    @State private var selectedChild: Child?
    @State private var showingAddChild = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Check students in or out and record daily activity updates.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))

                    if isLoading {
                        ProgressView().tint(AppConstants.Colors.accessibleYellow)
                    } else if children.isEmpty {
                        emptyPanel("No children are available for this school yet.")
                    } else {
                        ForEach(children) { child in
                            childCard(child)
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
        .navigationTitle("Children")
        .toolbar {
            if appSession.role?.canManageEvents == true {
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
        .sheet(item: $selectedChild) { child in
            ChildActivityComposerView(child: child) {
                Task { await loadChildren() }
            }
        }
        .sheet(isPresented: $showingAddChild) {
            AddChildView {
                Task { await loadChildren() }
            }
        }
        .task {
            await loadChildren()
        }
        .refreshable {
            await loadChildren()
        }
    }

    private func childCard(_ child: Child) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(child.fullName)
                .font(.headline)
                .foregroundColor(.white)
            HStack {
                Button("Check In") { recordAttendance(child, checkingIn: true) }
                Button("Check Out") { recordAttendance(child, checkingIn: false) }
                Button("Record") { selectedChild = child }
            }
            .buttonStyle(.bordered)
            .tint(AppConstants.Colors.accessibleYellow)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
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
    private func loadChildren() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            children = try await SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load children", error)
            isLoading = false
        }
    }

    private func recordAttendance(_ child: Child, checkingIn: Bool) {
        guard let schoolId = appSession.activeSchool?.id else { return }
        Task {
            do {
                try await SchoolWorkflowService.shared.recordAttendance(
                    schoolId: schoolId,
                    childId: child.id,
                    checkingIn: checkingIn,
                    notes: nil
                )
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not record attendance", error)
                }
            }
        }
    }
}

private struct AddChildView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    var onSaved: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Child") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
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
                    Button("Save") { save() }
                        .disabled(firstName.isEmpty || lastName.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        Task {
            do {
                try await SchoolWorkflowService.shared.addChild(
                    schoolId: schoolId,
                    firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not add child", error) }
            }
        }
    }
}

private struct ChildActivityComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let child: Child
    var onSaved: () -> Void

    @State private var activityType = "bowel_movement"
    @State private var notes = ""
    @State private var errorMessage: String?

    private let activityTypes = [
        ("bowel_movement", "Bowel Movement"),
        ("medication", "Medication"),
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
            .navigationTitle("Record Activity")
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
        guard let schoolId = appSession.activeSchool?.id else { return }
        Task {
            do {
                try await SchoolWorkflowService.shared.recordChildActivity(
                    schoolId: schoolId,
                    childId: child.id,
                    activityType: activityType,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                )
                await MainActor.run {
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not record activity", error) }
            }
        }
    }
}
