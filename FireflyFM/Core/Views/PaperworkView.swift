//
//  PaperworkView.swift
//  FireflyFM
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct PaperworkView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var assignments: [PaperworkAssignment] = []
    @State private var submissions: [PaperworkSubmission] = []
    @State private var profilesById: [UUID: UserProfile] = [:]
    @State private var uploadingAssignmentIds = Set<UUID>()
    @State private var isLoading = true
    @State private var showingAssignmentComposer = false
    @State private var importingForAssignment: PaperworkAssignment?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isLoading {
                        ProgressView().tint(AppConstants.Colors.accessibleYellow)
                    } else {
                        if appSession.role?.canManageSchool == true {
                            directorContent
                        } else {
                            parentContent
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
        .navigationTitle(appSession.role?.canManageSchool == true ? "Paperwork Review" : "Paperwork")
        .toolbar {
            if appSession.role?.canManageSchool == true {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAssignmentComposer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }
        }
        .sheet(isPresented: $showingAssignmentComposer) {
            PaperworkAssignmentComposerView {
                Task { await load() }
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importingForAssignment != nil },
                set: { if !$0 { importingForAssignment = nil } }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleSubmissionImport(result)
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appSession.activeSchool?.name ?? "School")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text(appSession.role?.canManageSchool == true ? "Review submissions and assign secure paperwork." : "Download assigned paperwork, upload completed files, and wait for director review.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.66))
        }
    }

    private var parentContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assigned")
                .font(.headline)
                .foregroundColor(.white)

            if assignments.isEmpty {
                emptyPanel("No paperwork assigned.")
            } else {
                ForEach(assignments) { assignment in
                    paperworkCard(assignment) {
                        HStack {
                            if assignment.filePath != nil {
                                Button("Download") { openFile(path: assignment.filePath) }
                            }
                            Button("Upload Completed") {
                                importingForAssignment = assignment
                            }
                            .disabled(uploadingAssignmentIds.contains(assignment.id))
                            Spacer()
                            Text(uploadingAssignmentIds.contains(assignment.id) ? "Uploading..." : statusText(for: assignment))
                                .font(.caption.bold())
                                .foregroundColor(statusColor(for: assignment))
                        }
                    }
                }
            }
        }
    }

    private var directorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Submissions")
                .font(.headline)
                .foregroundColor(.white)
            if submissions.isEmpty {
                emptyPanel("No submissions yet.")
            } else {
                ForEach(submissions) { submission in
                    submissionCard(submission)
                }
            }
        }
    }

    private func paperworkCard<Actions: View>(_ assignment: PaperworkAssignment, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(assignment.title)
                .font(.headline)
                .foregroundColor(.white)
            if let description = assignment.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }
            if let fileName = assignment.fileName {
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

    private func submissionCard(_ submission: PaperworkSubmission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(submission.fileName ?? "Paperwork submission")
                .font(.headline)
                .foregroundColor(.white)
            Label(profilesById[submission.submittedBy]?.displayName ?? "Submitted by school member", systemImage: "person.crop.circle")
                .font(.caption)
                .foregroundColor(.white.opacity(0.58))
            Text(submission.status.capitalized)
                .font(.caption.bold())
                .foregroundColor(submission.status == "accepted" ? .green : submission.status == "flagged" ? .red : AppConstants.Colors.accessibleYellow)
            if let reason = submission.flagReason, !reason.isEmpty {
                Text(reason)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
            }
            HStack {
                if submission.filePath != nil {
                    Button("Open") { openFile(path: submission.filePath) }
                }
                Button("Accept") { review(submission, status: "accepted", reason: nil) }
                Button("Flag") { review(submission, status: "flagged", reason: "Please review and resubmit this paperwork.") }
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

    private func statusText(for assignment: PaperworkAssignment) -> String {
        guard let submission = submissions.first(where: { $0.assignmentId == assignment.id }) else {
            return "Due"
        }
        switch submission.status {
        case "accepted": return "Accepted"
        case "flagged": return "Flagged"
        default: return "Received, pending review"
        }
    }

    private func statusColor(for assignment: PaperworkAssignment) -> Color {
        guard let submission = submissions.first(where: { $0.assignmentId == assignment.id }) else {
            return AppConstants.Colors.accessibleYellow
        }
        if submission.status == "accepted" { return .green }
        if submission.status == "flagged" { return .red }
        return .orange
    }

    @MainActor
    private func load() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            if appSession.role?.canManageSchool == true {
                assignments = []
                submissions = try await SchoolWorkflowService.shared.fetchPaperworkSubmissions(schoolId: schoolId)
            } else {
                async let loadedAssignments = SchoolWorkflowService.shared.fetchPaperworkAssignments(schoolId: schoolId)
                async let loadedSubmissions = SchoolWorkflowService.shared.fetchPaperworkSubmissions(schoolId: schoolId)
                assignments = try await loadedAssignments
                submissions = try await loadedSubmissions
            }
            profilesById = try await ProfileService.shared.fetchProfiles(ids: submissions.map(\.submittedBy))
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load paperwork", error)
            isLoading = false
        }
    }

    private func handleSubmissionImport(_ result: Result<[URL], Error>) {
        guard let assignment = importingForAssignment else { return }
        importingForAssignment = nil

        do {
            guard let url = try result.get().first else { return }
            Task {
                do {
                    await MainActor.run {
                        uploadingAssignmentIds.insert(assignment.id)
                        errorMessage = nil
                    }
                    try await SchoolWorkflowService.shared.submitPaperwork(assignment: assignment, fileURL: url)
                    await load()
                    await MainActor.run {
                        uploadingAssignmentIds.remove(assignment.id)
                    }
                } catch {
                    await MainActor.run {
                        uploadingAssignmentIds.remove(assignment.id)
                        errorMessage = AppErrorMessage.school("Could not upload paperwork", error)
                    }
                }
            }
        } catch {
            errorMessage = AppErrorMessage.school("Could not read selected file", error)
        }
    }

    private func review(_ submission: PaperworkSubmission, status: String, reason: String?) {
        Task {
            do {
                try await SchoolWorkflowService.shared.reviewPaperworkSubmission(id: submission.id, status: status, reason: reason)
                await load()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not review submission", error)
                }
            }
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

private struct PaperworkAssignmentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var members: [SchoolMember] = []
    @State private var parentSearchText = ""
    @State private var selectedParentIds = Set<UUID>()
    @State private var selectedFileURL: URL?
    @State private var showingFileImporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                    Button(selectedFileURL?.lastPathComponent ?? "Choose attachment") {
                        showingFileImporter = true
                    }
                }

                Section("Parents") {
                    TextField("Search parent name", text: $parentSearchText)

                    if selectedParents.isEmpty == false {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(selectedParents) { member in
                                HStack {
                                    Text(member.displayName)
                                    Spacer()
                                    Button("Remove") {
                                        selectedParentIds.remove(member.id)
                                    }
                                }
                            }
                        }
                    }

                    if members.isEmpty {
                        Text("No parents found for this school.")
                    } else if parentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Start typing a parent name to see matches.")
                            .foregroundColor(.secondary)
                    } else if parentSuggestions.isEmpty {
                        Text("No matching parents found.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(parentSuggestions) { member in
                            Button {
                                selectedParentIds.insert(member.id)
                                parentSearchText = ""
                            } label: {
                                HStack {
                                    Text(member.displayName)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Assign Paperwork")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Assign") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedParentIds.isEmpty || isSaving)
                }
            }
            .task {
                await loadParents()
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                selectedFileURL = try? result.get().first
            }
        }
    }

    private var selectedParents: [SchoolMember] {
        members
            .filter { selectedParentIds.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var parentSuggestions: [SchoolMember] {
        let query = parentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        return members
            .filter { !selectedParentIds.contains($0.id) }
            .filter { $0.displayName.lowercased().contains(query) }
            .sorted { lhs, rhs in
                score(lhs.displayName, query: query) < score(rhs.displayName, query: query)
            }
            .prefix(5)
            .map { $0 }
    }

    private func score(_ name: String, query: String) -> Int {
        let lower = name.lowercased()
        if lower.hasPrefix(query) { return 0 }
        if lower.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 1 }
        return 2
    }

    @MainActor
    private func loadParents() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        do {
            members = try await SchoolService.shared.fetchMembers(schoolId: schoolId, role: .parent)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load parents", error)
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.createPaperworkAssignment(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    fileURL: selectedFileURL,
                    parentIds: Array(selectedParentIds)
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not assign paperwork", error)
                }
            }
        }
    }
}
