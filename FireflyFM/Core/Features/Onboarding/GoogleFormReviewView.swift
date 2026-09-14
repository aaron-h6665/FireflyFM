import SwiftUI
import Observation

@MainActor
@Observable
final class GoogleFormReviewModel {
    private(set) var imports: [GoogleFormImport] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(schoolId: UUID, filter: GoogleFormResponseArchiveFilter) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let records = try await SchoolWorkflowService.shared.fetchGoogleFormImports(schoolId: schoolId, status: nil)
            imports = records.filter { filter.includes(status: $0.status) }
        } catch where AppErrorMessage.isCancellation(error) {} catch {
            errorMessage = AppErrorMessage.school("Could not load form responses", error)
        }
    }
}

struct GoogleFormReviewView: View {
    let school: School
    @State private var model = GoogleFormReviewModel()
    @State private var filter: GoogleFormResponseArchiveFilter = .active

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    filterPicker
                    if model.isLoading {
                        ProgressView().tint(AppConstants.Colors.accessibleYellow)
                    } else if model.imports.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.imports) { item in
                            NavigationLink {
                                GoogleFormImportDetailView(school: school, item: item) {
                                    Task { await load() }
                                }
                            } label: {
                                responseRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage).font(.caption).foregroundColor(.red)
                    }
                }
                .padding()
            }
            .refreshable { await load() }
        }
        .navigationTitle("Form Responses")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: filter) { _, _ in Task { await load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(school.name).font(.caption.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
            Text("Review Form Responses").font(.largeTitle.bold()).foregroundColor(AppConstants.Colors.primaryText)
            Text("Review imported Form evidence before granting access or creating a child connection.")
                .font(.subheadline).foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
        }
    }

    private var filterPicker: some View {
        Picker("Response filter", selection: $filter) {
            ForEach(GoogleFormResponseArchiveFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("google-form-review-filter")
    }

    private var emptyState: some View {
        Text(filter == .active ? "No form responses need review." : "No archived form responses yet.")
            .font(.subheadline).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(AppConstants.Colors.card).cornerRadius(10)
    }

    private func responseRow(_ item: GoogleFormImport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: GoogleFormResponsePresentation.isArchived(status: item.status)
                  ? "archivebox.fill"
                  : (item.status == "ambiguous" ? "questionmark.circle.fill" : "doc.text.magnifyingglass"))
                .foregroundColor(GoogleFormResponsePresentation.isArchived(status: item.status)
                                 ? .secondary
                                 : (item.status == "ambiguous" ? .orange : AppConstants.Colors.accessibleYellow))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.respondentEmail ?? "Form response").font(.subheadline.bold()).foregroundColor(AppConstants.Colors.primaryText)
                Text(item.responseSubmittedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Submitted time unavailable")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(statusTitle(item.status)).font(.caption.bold()).foregroundColor(statusColor(item.status))
        }
        .padding().background(AppConstants.Colors.card).cornerRadius(10)
    }

    private func statusTitle(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "approved": .green
        case "rejected", "changes_requested", "error": .red
        case "ambiguous": .orange
        default: .secondary
        }
    }

    private func load() async {
        await model.load(schoolId: school.id, filter: filter)
    }
}

enum GoogleFormResponseArchiveFilter: String, CaseIterable, Identifiable {
    case active
    case archived

    var id: String { rawValue }
    var title: String { self == .active ? "Active" : "Archived" }

    func includes(status: String) -> Bool {
        GoogleFormResponsePresentation.isArchived(status: status) == (self == .archived)
    }
}

enum GoogleFormResponsePresentation {
    private static let reviewableStatuses = Set(["pending_review", "ambiguous", "error"])
    private static let archivedStatuses = Set(["approved", "rejected", "changes_requested"])

    static func canReview(status: String) -> Bool {
        reviewableStatuses.contains(status)
    }

    static func isArchived(status: String) -> Bool {
        archivedStatuses.contains(status)
    }
}

private struct GoogleFormImportDetailView: View {
    let school: School
    let item: GoogleFormImport
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var attachments: [GoogleFormImportAttachment] = []
    @State private var existingChildren: [Child] = []
    @State private var matchedChildId: UUID?
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canReview: Bool {
        GoogleFormResponsePresentation.canReview(status: item.status)
    }

    var body: some View {
        Form {
            Section("Submission") {
                LabeledContent("Responder", value: item.respondentEmail ?? "Not provided")
                LabeledContent("Intake", value: item.childConnectionRequestId == nil ? "Role form" : "Parent child intake")
                LabeledContent("Status", value: item.status.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            if item.childConnectionRequestId != nil && item.status == "pending_review" {
                Section("Child decision") {
                    Text("Approve as a new child, or select an existing child at this school. Parents never see this matching list.")
                        .font(.caption).foregroundColor(.secondary)
                    Picker("Existing child", selection: $matchedChildId) {
                        Text("Create a new child").tag(UUID?.none)
                        ForEach(existingChildren) { child in
                            Text("\(child.firstName) \(child.lastName)").tag(Optional(child.id))
                        }
                    }
                }
            }
            Section("Form answers") {
                ForEach(item.displayedAnswers) { answer in
                    LabeledContent(answer.title, value: answer.value)
                }
            }
            Section("Documents") {
                if attachments.isEmpty { Text("No uploaded documents recorded.").foregroundColor(.secondary) }
                ForEach(attachments) { attachment in
                    Label(attachment.fileName, systemImage: "doc.fill")
                }
            }
            Section("Review decision") {
                if canReview {
                    TextField("Reviewer note", text: $note, axis: .vertical)
                } else {
                    Label("This response is archived and cannot be reviewed again.", systemImage: "archivebox.fill")
                        .foregroundColor(.secondary)
                    if let reviewNote = item.reviewNote, reviewNote.isEmpty == false {
                        LabeledContent("Reviewer note", value: reviewNote)
                    }
                    if let reviewedAt = item.reviewedAt {
                        LabeledContent("Reviewed", value: reviewedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
        }
        .navigationTitle("Response Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if canReview {
                HStack {
                    Button("Reject", role: .destructive) { review(status: "rejected") }
                    Spacer()
                    Button("Request changes") { review(status: "changes_requested") }
                    Button("Approve") { review(status: "approved") }.buttonStyle(.borderedProminent)
                }
                .padding().background(.bar)
            }
        }
        .task {
            do {
                attachments = try await SchoolWorkflowService.shared.fetchGoogleFormImportAttachments(importId: item.id)
                if item.childConnectionRequestId != nil {
                    existingChildren = try await SchoolWorkflowService.shared.fetchChildren(schoolId: school.id)
                }
            }
            catch { errorMessage = AppErrorMessage.school("Could not load documents", error) }
        }
        .disabled(isSaving)
    }

    private func review(status: String) {
        guard canReview else {
            errorMessage = "This response has already been reviewed and archived."
            return
        }
        guard status == "approved" || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            errorMessage = "Add a note explaining the requested changes or rejection."
            return
        }
        isSaving = true
        Task {
            do {
                try await SchoolWorkflowService.shared.reviewGoogleFormImport(
                    importId: item.id, status: status, matchedChildId: matchedChildId, note: note.isEmpty ? nil : note
                )
                await MainActor.run { isSaving = false; onChanged(); dismiss() }
            } catch {
                await MainActor.run { isSaving = false; errorMessage = AppErrorMessage.school("Could not save the review", error) }
            }
        }
    }
}
