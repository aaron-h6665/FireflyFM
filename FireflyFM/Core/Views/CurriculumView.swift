//
//  CurriculumView.swift
//  FireflyFM
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct CurriculumView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var resources: [CurriculumResource] = []
    @State private var assignments: [TrainingAssignment] = []
    @State private var submissions: [TrainingSubmission] = []
    @State private var isLoading = true
    @State private var showingResourceComposer = false
    @State private var showingTrainingComposer = false
    @State private var importingTrainingAssignment: TrainingAssignment?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("School curriculum resources and assigned teacher training.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))

                    if isLoading {
                        ProgressView().tint(AppConstants.Colors.accessibleYellow)
                    } else {
                        resourcesSection
                        trainingSection
                        if appSession.role?.canManageSchool == true {
                            submissionsSection
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
        .navigationTitle("Curriculum")
        .toolbar {
            if appSession.role?.canManageSchool == true {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingResourceComposer = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    Button {
                        showingTrainingComposer = true
                    } label: {
                        Image(systemName: "person.badge.clock")
                    }
                }
            }
        }
        .sheet(isPresented: $showingResourceComposer) {
            CurriculumResourceComposerView { Task { await load() } }
        }
        .sheet(isPresented: $showingTrainingComposer) {
            TrainingAssignmentComposerView { Task { await load() } }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importingTrainingAssignment != nil },
                set: { if !$0 { importingTrainingAssignment = nil } }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleTrainingImport(result)
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Curriculum Resources")
                .font(.headline)
                .foregroundColor(.white)
            if resources.isEmpty {
                emptyPanel("No curriculum resources yet.")
            } else {
                ForEach(resources) { resource in
                    card(title: resource.title, subtitle: resource.description, fileName: resource.fileName) {
                        if resource.filePath != nil {
                            Button("Open") { openFile(path: resource.filePath) }
                        }
                    }
                }
            }
        }
    }

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Assignments")
                .font(.headline)
                .foregroundColor(.white)
            if assignments.isEmpty {
                emptyPanel("No training assignments.")
            } else {
                ForEach(assignments) { assignment in
                    card(title: assignment.title, subtitle: assignment.description, fileName: assignment.fileName) {
                        HStack {
                            if assignment.filePath != nil {
                                Button("Open") { openFile(path: assignment.filePath) }
                            }
                            if appSession.role == .teacher {
                                Button("Upload Response") {
                                    importingTrainingAssignment = assignment
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var submissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teacher Submissions")
                .font(.headline)
                .foregroundColor(.white)
            if submissions.isEmpty {
                emptyPanel("No teacher submissions yet.")
            } else {
                ForEach(submissions) { submission in
                    card(title: submission.fileName ?? "Training submission", subtitle: submission.status.capitalized, fileName: nil) {
                        if submission.filePath != nil {
                            Button("Open") { openFile(path: submission.filePath) }
                        }
                    }
                }
            }
        }
    }

    private func card<Actions: View>(title: String, subtitle: String?, fileName: String?, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }
            if let fileName {
                Label(fileName, systemImage: "paperclip")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
            actions()
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
    private func load() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let loadedResources = SchoolWorkflowService.shared.fetchCurriculumResources(schoolId: schoolId)
            async let loadedAssignments = SchoolWorkflowService.shared.fetchTrainingAssignments(schoolId: schoolId)
            async let loadedSubmissions = SchoolWorkflowService.shared.fetchTrainingSubmissions(schoolId: schoolId)
            resources = try await loadedResources
            assignments = try await loadedAssignments
            submissions = try await loadedSubmissions
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load curriculum", error)
            isLoading = false
        }
    }

    private func handleTrainingImport(_ result: Result<[URL], Error>) {
        guard let assignment = importingTrainingAssignment else { return }
        importingTrainingAssignment = nil
        do {
            guard let url = try result.get().first else { return }
            Task {
                do {
                    try await SchoolWorkflowService.shared.submitTraining(assignment: assignment, fileURL: url)
                    await load()
                } catch {
                    await MainActor.run {
                        errorMessage = AppErrorMessage.school("Could not upload training", error)
                    }
                }
            }
        } catch {
            errorMessage = AppErrorMessage.school("Could not read selected file", error)
        }
    }

    private func openFile(path: String?) {
        guard let path else { return }
        Task {
            do {
                let url = try await SchoolService.shared.signedPrivateFileURL(path: path)
                await MainActor.run { UIApplication.shared.open(url) }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not open file", error) }
            }
        }
    }
}

private struct CurriculumResourceComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var selectedFileURL: URL?
    @State private var showingImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Resource") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                    Button(selectedFileURL?.lastPathComponent ?? "Choose file") { showingImporter = true }
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("New Resource")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                selectedFileURL = try? result.get().first
            }
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        Task {
            do {
                try await SchoolWorkflowService.shared.createCurriculumResource(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    fileURL: selectedFileURL
                )
                await MainActor.run {
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not add curriculum resource", error) }
            }
        }
    }
}

private struct TrainingAssignmentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var teachers: [SchoolMember] = []
    @State private var selectedTeacherIds = Set<UUID>()
    @State private var selectedFileURL: URL?
    @State private var showingImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Training") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                    Button(selectedFileURL?.lastPathComponent ?? "Choose attachment") { showingImporter = true }
                }
                Section("Teachers") {
                    if teachers.isEmpty {
                        Text("No teachers found for this school.")
                    } else {
                        ForEach(teachers) { teacher in
                            Toggle(teacher.displayName, isOn: Binding(
                                get: { selectedTeacherIds.contains(teacher.id) },
                                set: { selected in
                                    if selected {
                                        selectedTeacherIds.insert(teacher.id)
                                    } else {
                                        selectedTeacherIds.remove(teacher.id)
                                    }
                                }
                            ))
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("Assign Training")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTeacherIds.isEmpty)
                }
            }
            .task { await loadTeachers() }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                selectedFileURL = try? result.get().first
            }
        }
    }

    @MainActor
    private func loadTeachers() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        do {
            teachers = try await SchoolService.shared.fetchMembers(schoolId: schoolId, role: .teacher)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load teachers", error)
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        Task {
            do {
                try await SchoolWorkflowService.shared.createTrainingAssignment(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    fileURL: selectedFileURL,
                    teacherIds: Array(selectedTeacherIds)
                )
                await MainActor.run {
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not assign training", error) }
            }
        }
    }
}
