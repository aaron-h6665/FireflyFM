//
//  DocumentFeedbackLoopView.swift
//  FireflyFM
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentFeedbackLoopView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var requirements: [OnboardingRequirement] = []
    @State private var submissions: [DocumentSubmission] = []
    @State private var profilesById: [UUID: UserProfile] = [:]
    @State private var currentUserId: UUID?
    @State private var importingRequirement: OnboardingRequirement?
    @State private var showingComposer = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canAssign: Bool {
        appSession.role?.canManageSchool == true
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isLoading {
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    } else {
                        myRequiredDocuments
                        if canAssign {
                            reviewQueue
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
            .refreshable { await load() }
        }
        .navigationTitle("Documents")
        .toolbar {
            if canAssign {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingComposer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                    }
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            RequirementComposerView {
                Task { await load() }
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importingRequirement != nil },
                set: { if !$0 { importingRequirement = nil } }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleSubmissionImport(result)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Required Documents")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text("Assign, upload, verify, or flag secure files without exposing public document URLs.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.66))
        }
    }

    private var myRequiredDocuments: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Required Items")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            let items = requirementsForCurrentUser
            if items.isEmpty {
                emptyPanel("No required documents are assigned to you.")
            } else {
                ForEach(items) { requirement in
                    requirementCard(requirement)
                }
            }
        }
    }

    private var reviewQueue: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Queue")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            if submissions.isEmpty {
                emptyPanel("No document submissions yet.")
            } else {
                ForEach(submissions) { submission in
                    submissionCard(submission)
                }
            }
        }
    }

    private var requirementsForCurrentUser: [OnboardingRequirement] {
        requirements.filter { requirement in
            if let currentUserId, requirement.targetUserId == currentUserId {
                return true
            }
            if let role = appSession.role, requirement.targetRole == role {
                return true
            }
            return requirement.targetUserId == nil && requirement.targetRole == nil
        }
    }

    private func requirementCard(_ requirement: OnboardingRequirement) -> some View {
        let submission = submissions.first { $0.requirementId == requirement.id && $0.submittedBy == currentUserId }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(requirement.title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(statusText(for: submission))
                    .font(.caption.bold())
                    .foregroundColor(statusColor(for: submission))
            }

            if let description = requirement.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            if let message = submission?.reviewerMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .padding(8)
                    .background(AppConstants.Colors.background.opacity(0.45))
                    .cornerRadius(8)
            }

            HStack {
                if requirement.filePath != nil {
                    Button("Download") { openFile(path: requirement.filePath) }
                }
                Button(submission == nil ? "Upload Completed" : "Replace Upload") {
                    importingRequirement = requirement
                }
                Spacer()
            }
            .buttonStyle(.bordered)
            .tint(AppConstants.Colors.accessibleYellow)
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func submissionCard(_ submission: DocumentSubmission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(requirements.first(where: { $0.id == submission.requirementId })?.title ?? "Document submission")
                .font(.headline)
                .foregroundColor(.white)
            Label(profilesById[submission.submittedBy]?.displayName ?? "Submitted user", systemImage: "person.crop.circle")
                .font(.caption)
                .foregroundColor(.white.opacity(0.58))
            Text(submission.status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption.bold())
                .foregroundColor(statusColor(for: submission))
            if let message = submission.reviewerMessage, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            HStack {
                if submission.filePath != nil {
                    Button("Open") { openFile(path: submission.filePath) }
                }
                Button("Approve") { review(submission, status: "verified", message: nil) }
                Button("Flag") { review(submission, status: "flagged", message: "Please review and resubmit this document.") }
            }
            .buttonStyle(.bordered)
            .tint(AppConstants.Colors.accessibleYellow)
        }
        .padding()
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

    private func statusText(for submission: DocumentSubmission?) -> String {
        guard let submission else { return "Due" }
        switch submission.status {
        case "verified": return "Verified"
        case "flagged": return "Flagged"
        default: return "Received, pending review"
        }
    }

    private func statusColor(for submission: DocumentSubmission?) -> Color {
        guard let submission else { return AppConstants.Colors.accessibleYellow }
        return statusColor(for: submission)
    }

    private func statusColor(for submission: DocumentSubmission) -> Color {
        switch submission.status {
        case "verified": return .green
        case "flagged": return .red
        default: return .orange
        }
    }

    @MainActor
    private func load() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isLoading = true
        errorMessage = nil

        do {
            currentUserId = try await ProfileService.shared.currentUserId()
            async let loadedRequirements = SchoolWorkflowService.shared.fetchOnboardingRequirements(schoolId: schoolId)
            async let loadedSubmissions = SchoolWorkflowService.shared.fetchDocumentSubmissions(schoolId: schoolId)
            requirements = try await loadedRequirements
            submissions = try await loadedSubmissions
            profilesById = try await ProfileService.shared.fetchProfiles(ids: submissions.map(\.submittedBy))
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load documents", error)
            isLoading = false
        }
    }

    private func handleSubmissionImport(_ result: Result<[URL], Error>) {
        guard let requirement = importingRequirement else { return }
        importingRequirement = nil

        do {
            guard let url = try result.get().first else { return }
            Task {
                do {
                    try await SchoolWorkflowService.shared.submitRequiredDocument(requirement: requirement, fileURL: url)
                    await load()
                } catch {
                    await MainActor.run {
                        errorMessage = AppErrorMessage.school("Could not upload document", error)
                    }
                }
            }
        } catch {
            errorMessage = AppErrorMessage.school("Could not read selected file", error)
        }
    }

    private func review(_ submission: DocumentSubmission, status: String, message: String?) {
        Task {
            do {
                try await SchoolWorkflowService.shared.reviewRequiredDocument(submissionId: submission.id, status: status, message: message)
                await load()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not review document", error)
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

private struct RequirementComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var requirementType = "contract"
    @State private var targetRole: SchoolRole = .schoolDirector
    @State private var fileURL: URL?
    @State private var showingImporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var availableRoles: [SchoolRole] {
        if appSession.role == .hqDirector {
            return [.schoolDirector, .teacher, .parent]
        }
        return [.teacher, .parent]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Requirement") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                    Picker("Type", selection: $requirementType) {
                        Text("Contract").tag("contract")
                        Text("Certificate").tag("certificate")
                        Text("License").tag("license")
                        Text("Physical").tag("physical")
                        Text("Enrollment Pack").tag("enrollment_pack")
                        Text("Other").tag("other")
                    }
                    Picker("Assign to", selection: $targetRole) {
                        ForEach(availableRoles) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    Button(fileURL?.lastPathComponent ?? "Attach template file") {
                        showingImporter = true
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Assign Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Assigning" : "Assign") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                if availableRoles.contains(targetRole) == false {
                    targetRole = availableRoles.first ?? .parent
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                fileURL = try? result.get().first
            }
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await SchoolWorkflowService.shared.createOnboardingRequirement(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    requirementType: requirementType,
                    targetRole: targetRole,
                    targetUserId: nil,
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
                    errorMessage = AppErrorMessage.school("Could not assign document", error)
                }
            }
        }
    }
}
