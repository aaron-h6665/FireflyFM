//
//  AssignmentDetailView.swift
//  FireflyFM
//

import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum AssignmentConversationLayout {
    static func maximumHeight(for screenHeight: CGFloat) -> CGFloat {
        min(420, max(240, screenHeight * 0.35))
    }
}
private enum AssignmentConversationEntry: Identifiable {
    case message(AssignmentFeedbackMessage)
    case event(AssignmentEvent)

    var id: String {
        switch self {
        case .message(let message): "message-\(message.id.uuidString)"
        case .event(let event): "event-\(event.id.uuidString)"
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message): message.createdAt ?? .distantPast
        case .event(let event): event.createdAt ?? .distantPast
        }
    }
}
struct AssignmentDetailView: View {
    let assignmentId: UUID
    var onChanged: () -> Void = {}

    @State private var model = AssignmentDetailModel()
    @State private var feedbackText = ""
    @State private var medicationName = ""
    @State private var medicationDosage = ""
    @State private var medicationSchedule = Date()
    @State private var medicationInstructions = ""
    @State private var medicationRepeatRule = ""
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()
    @State private var structuredNotes = ""
    @State private var selectedFileURLs: [URL] = []
    @State private var showingImporter = false
    @State private var selectedReviewUserId: UUID?
    @State private var reviewMessage = ""
    @State private var reviewScore: Int?
    @State private var waiverReason = ""
    @State private var showingWaiverConfirmation = false
    @State private var showingEditor = false
    @State private var pendingLifecycleAction: AssignmentLifecycleAction?
    @State private var previewURL: URL?
    @State private var webURL: URL?
    @State private var scoreEditorSubmission: AssignmentSubmission?
    @State private var retroactiveScore: Int?
    @State private var isActivityExpanded = false
    @State private var commentDrafts: [UUID: String] = [:]
    @State private var conversationAtBottom: [UUID: Bool] = [:]
    @State private var conversationsWithNewMessages = Set<UUID>()
    @State private var submissionMutationKey = UUID().uuidString
    @State private var reviewMutationKeys: [String: String] = [:]
    @State private var commentMutationKeys: [UUID: String] = [:]
    private var bundle: AssignmentDetailBundle? { model.bundle }
    private var profilesById: [UUID: UserProfile] { model.profilesById }
    private var currentUserId: UUID? { model.currentUserId }
    private var childRequirementBinding: ChildRequirementBinding { model.childRequirementBinding }
    private var isLoading: Bool { model.phase.isLoading }
    private var isSaving: Bool { model.isSaving }
    private var errorMessage: String? { model.errorMessage }

    private var assignment: Assignment? { bundle?.assignment }

    private var mySubmission: AssignmentSubmission? {
        guard let currentUserId else { return nil }
        return bundle?.submissions.first { $0.submittedBy == currentUserId }
    }

    private var mySubmissions: [AssignmentSubmission] {
        guard let currentUserId else { return [] }
        return bundle?.submissions.filter { $0.submittedBy == currentUserId } ?? []
    }

    private var isRead: Bool {
        guard let currentUserId else { return false }
        return bundle?.readReceipts.contains { $0.userId == currentUserId } == true
    }

    private var canSubmit: Bool {
        bundle?.capabilities.canSubmit == true
    }

    private var canReview: Bool {
        bundle?.capabilities.canReview == true
    }

    private var canManageAssignment: Bool {
        bundle?.capabilities.canManage == true
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    } else if let bundle {
                        header(bundle.assignment)
                        materialsSection(bundle.materials)
                        if bundle.capabilities.isRecipient {
                            submitSection(bundle.assignment)
                            feedbackSection(
                                bundle,
                                recipientId: bundle.capabilities.userId,
                                title: conversationTitle(for: bundle.capabilities.userId, bundle: bundle)
                            )
                            recipientActivitySection(recipientEvents(in: bundle))
                        }
                        if canReview {
                            reviewSection(bundle)
                            managementHistorySection(bundle.events)
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
            if let pendingLifecycleAction {
                AssignmentConfirmationOverlay(
                    action: pendingLifecycleAction,
                    onCancel: { self.pendingLifecycleAction = nil },
                    onConfirm: {
                        self.pendingLifecycleAction = nil
                        changeStatus(to: pendingLifecycleAction.targetStatus)
                    }
                )
            }
        }
        .navigationTitle("Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManageAssignment, let assignment {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if assignment.status != "archived" {
                            Button {
                                showingEditor = true
                            } label: {
                                Label("Edit Assignment", systemImage: "pencil")
                            }
                        }
                        if assignment.status == "draft" || assignment.status == "scheduled" {
                            Button {
                                changeStatus(to: "published")
                            } label: {
                                Label("Publish Now", systemImage: "paperplane.fill")
                            }
                        }
                        if assignment.status == "published" || assignment.status == "scheduled" {
                            Button {
                                pendingLifecycleAction = .close
                            } label: {
                                Label("Close", systemImage: "lock.fill")
                            }
                        }
                        if assignment.status == "closed" {
                            Button { changeStatus(to: "published") } label: {
                                Label("Reopen", systemImage: "lock.open.fill")
                            }
                        }
                        if assignment.status == "archived" {
                            Button { changeStatus(to: "closed") } label: {
                                Label("Restore as Closed", systemImage: "arrow.uturn.backward.circle.fill")
                            }
                        } else {
                            Button(role: .destructive) {
                                pendingLifecycleAction = .archive
                            } label: {
                                Label("Archive", systemImage: "archivebox.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if let urls = try? result.get() {
                selectedFileURLs.append(contentsOf: urls.filter { selectedFileURLs.contains($0) == false })
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let assignment {
                AssignmentEditorView(assignment: assignment, materials: bundle?.materials ?? []) {
                    Task {
                        await load()
                        onChanged()
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { webURL != nil },
            set: { if !$0 { webURL = nil } }
        )) {
            if let webURL { AssignmentSafariView(url: webURL).ignoresSafeArea() }
        }
        .sheet(item: $scoreEditorSubmission) { submission in
            AssignmentScoreEditor(
                score: $retroactiveScore,
                attemptNumber: submission.attemptNumber ?? 1,
                onCancel: { scoreEditorSubmission = nil },
                onSave: { updateScore(for: submission) }
            )
        }
        .quickLookPreview($previewURL)
        .confirmationDialog(
            "Waive this onboarding requirement?",
            isPresented: $showingWaiverConfirmation,
            titleVisibility: .visible
        ) {
            Button("Waive Requirement", role: .destructive) { waiveOnboardingRequirement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recorded reason will remain in the audit history, and this requirement will no longer block access.")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(assignment.category.title)
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppConstants.Colors.accessibleYellow)
                    .cornerRadius(8)
                if let status = assignment.status {
                    Text(submissionStatusTitle(status))
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(AppConstants.Colors.raised)
                        .cornerRadius(8)
                }
                Spacer()
                if let dueAt = assignment.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                }
            }
            Text(assignment.title)
                .font(.largeTitle.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            if let description = assignment.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func materialsSection(_ materials: [AssignmentMaterial]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Materials")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            if materials.isEmpty {
                smallPanel("No materials attached.")
            } else {
                ForEach(materials) { material in
                    HStack {
                        Label(material.title ?? material.fileName ?? material.url ?? "Material", systemImage: materialIcon(material))
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Spacer()
                        if material.privateFilePath != nil {
                            Button("Preview") { previewFile(material) }
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .tint(AppConstants.Colors.accessibleYellow)
                    .padding()
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                    if let value = material.url, let url = URL(string: value) {
                        AssignmentLinkPreview(url: url)
                            .frame(height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { webURL = url }
                            .contextMenu {
                                Button("Open in Safari") { UIApplication.shared.open(url) }
                            }
                    }
                }
            }
        }
    }

    private func submitSection(_ assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Submission")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            if let mySubmission {
                Text("Latest attempt: \(submissionStatusTitle(mySubmission.status)) · \(mySubmission.submittedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Submitted")")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                if let message = mySubmission.reviewerMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                        .padding(8)
                        .background(AppConstants.Colors.background.opacity(0.45))
                        .cornerRadius(8)
                }
                if mySubmission.reviewedAt != nil || mySubmission.score != nil {
                    AssignmentScoreSummary(
                        submission: mySubmission,
                        reviewerName: mySubmission.reviewedBy.flatMap { profilesById[$0]?.displayName }
                    )
                }
            }

            if canSubmit {
                structuredChildRecordFields

                TextEditor(text: $feedbackText)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .padding(8)
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)

                Button(selectedFileURLs.isEmpty ? "Attach files, photos, or videos" : "Add More Attachments") {
                    showingImporter = true
                }
                .buttonStyle(.bordered)
                .tint(AppConstants.Colors.accessibleYellow)

                ForEach(selectedFileURLs, id: \.self) { url in
                    HStack {
                        Label(url.lastPathComponent, systemImage: "paperclip")
                            .lineLimit(1)
                        Spacer()
                        Button("Remove") { selectedFileURLs.removeAll { $0 == url } }
                    }
                    .font(.caption)
                }

                Button(mySubmission == nil ? "Submit Assignment" : "Submit Revised Attempt") {
                    submit(assignment)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppConstants.Colors.accessibleYellow)
                .disabled(isSaving || submissionIsIncomplete)
            } else if mySubmission == nil {
                smallPanel(assignment.status == "archived"
                    ? "This assignment is archived and read-only."
                    : "This assignment is closed and read-only until the creator reopens it.")
            } else if assignment.allowResubmission == false {
                smallPanel("The assignment creator has disabled revised attempts. Your submitted version remains in history.")
            } else {
                smallPanel("A revised attempt becomes available if the assignment creator requests changes.")
            }

            if mySubmissions.isEmpty == false {
                Divider().overlay(.white.opacity(0.12))
                Text("Attempt History")
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                attemptHistory(mySubmissions, bundle: bundle)
            }
        }
        .padding()
        .background(AppConstants.Colors.card.opacity(0.72))
        .cornerRadius(8)
        .accessibilityIdentifier("assignment-recipient-panel")
    }

    @ViewBuilder
    private var structuredChildRecordFields: some View {
        switch childRequirementBinding {
        case .medicationAuthorization:
            VStack(alignment: .leading, spacing: 10) {
                Label("Medication authorization", systemImage: "pills.fill").font(.subheadline.bold())
                TextField("Medication name", text: $medicationName)
                TextField("Dosage", text: $medicationDosage)
                DatePicker("First due time", selection: $medicationSchedule)
                TextField("Schedule or repeat rule", text: $medicationRepeatRule)
                TextField("Administration instructions", text: $medicationInstructions, axis: .vertical).lineLimit(2...5)
                Text("Upload the signed authorization below. These values are reviewed with that same file and become the verified medication instruction after approval.")
                    .font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
            }
            .padding().background(AppConstants.Colors.background.opacity(0.45)).cornerRadius(8)
        case .immunizationRecord, .medicalClearance, .childDocument, .consent:
            VStack(alignment: .leading, spacing: 10) {
                Label("Verified child document", systemImage: "checkmark.seal.fill").font(.subheadline.bold())
                Toggle("Document has an expiry date", isOn: $hasExpiryDate)
                if hasExpiryDate { DatePicker("Expires", selection: $expiryDate, displayedComponents: .date) }
                TextField("Details for the reviewer", text: $structuredNotes, axis: .vertical).lineLimit(2...4)
                Text("The approved upload is referenced from the child profile; it is not copied or uploaded again.")
                    .font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
            }
            .padding().background(AppConstants.Colors.background.opacity(0.45)).cornerRadius(8)
        case .emergencyInformation:
            VStack(alignment: .leading, spacing: 10) {
                Label("Emergency information", systemImage: "cross.case.fill").font(.subheadline.bold())
                TextField("Emergency details", text: $structuredNotes, axis: .vertical).lineLimit(3...6)
                Text("Attach the school’s completed form below. Staff will review the form and these structured details together.")
                    .font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
            }
            .padding().background(AppConstants.Colors.background.opacity(0.45)).cornerRadius(8)
        case .none:
            EmptyView()
        }
    }

    private var submissionIsIncomplete: Bool {
        if childRequirementBinding != .none && selectedFileURLs.isEmpty { return true }
        if childRequirementBinding == .medicationAuthorization {
            return medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || medicationDosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return selectedFileURLs.isEmpty && feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var structuredSubmissionPayload: [String: FireflyJSONValue] {
        var payload: [String: FireflyJSONValue] = [:]
        switch childRequirementBinding {
        case .medicationAuthorization:
            payload["medication_name"] = .string(medicationName.trimmingCharacters(in: .whitespacesAndNewlines))
            payload["dosage"] = .string(medicationDosage.trimmingCharacters(in: .whitespacesAndNewlines))
            payload["scheduled_at"] = .string(ISO8601DateFormatter().string(from: medicationSchedule))
            payload["instructions"] = .string(medicationInstructions.trimmingCharacters(in: .whitespacesAndNewlines))
            payload["repeat_rule"] = .string(medicationRepeatRule.trimmingCharacters(in: .whitespacesAndNewlines))
        case .immunizationRecord, .medicalClearance, .childDocument, .consent:
            if hasExpiryDate { payload["expires_on"] = .string(DateOnlyCoding.string(from: expiryDate)) }
            if !structuredNotes.isEmpty { payload["notes"] = .string(structuredNotes) }
        case .emergencyInformation:
            payload["emergency_details"] = .string(structuredNotes)
        case .none:
            break
        }
        return payload
    }

    private func reviewSection(_ bundle: AssignmentDetailBundle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            let userIds = reviewUserIds(bundle)
            if userIds.isEmpty {
                smallPanel("No other recipients are available to review.")
            } else {
                reviewRecipientSelector(userIds)

                if bundle.assignment.category == .onboarding,
                   bundle.recipients.contains(where: { [.accepted, .excused].contains($0.completionStatus) }) == false {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Waiver reason (required)", text: $waiverReason, axis: .vertical)
                            .padding(12)
                            .background(AppConstants.Colors.card)
                            .cornerRadius(8)
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Button {
                            showingWaiverConfirmation = true
                        } label: {
                            Label("Waive Requirement", systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(isSaving || waiverReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Use a waiver only when the requirement is not needed. A reason is required and remains visible in the audit history.")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                    }
                }

                if let userId = selectedReviewUserId ?? userIds.first {
                    let attempts = bundle.submissions.filter { $0.submittedBy == userId }
                    if let latest = attempts.first {
                        submissionPreview(latest, bundle: bundle)

                        if ["submitted", "resubmitted"].contains(latest.status) {
                            TextField("Decision feedback", text: $reviewMessage, axis: .vertical)
                                .padding(12)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(8)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)

                            AssignmentScoreRail(score: $reviewScore)

                            HStack {
                                Button {
                                    review(latest, status: "changes_requested")
                                } label: {
                                    Label("Request Changes", systemImage: "arrow.uturn.backward")
                                }
                                .disabled(isSaving || reviewMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("assignment-request-changes")
                                Button {
                                    review(latest, status: "accepted")
                                } label: {
                                    Label("Accept", systemImage: "checkmark")
                                }
                                .disabled(isSaving)
                                .accessibilityIdentifier("assignment-accept")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppConstants.Colors.accessibleYellow)
                        } else {
                            smallPanel("This attempt has already been reviewed. A new attempt appears only after changes are requested.")
                        }

                        Text("Attempt History")
                            .font(.subheadline.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        attemptHistory(attempts, bundle: bundle)
                        feedbackSection(
                            bundle,
                            recipientId: userId,
                            title: conversationTitle(for: userId, bundle: bundle)
                        )
                    } else {
                        smallPanel("This recipient has not started yet.")
                    }
                }
            }
        }
        .accessibilityIdentifier("assignment-creator-panel")
    }

    private func reviewRecipientSelector(_ userIds: [UUID]) -> some View {
        HStack(spacing: 10) {
            Button {
                moveReviewRecipient(by: -1, userIds: userIds)
            } label: {
                Image(systemName: "chevron.left")
            }

            Menu {
                ForEach(userIds, id: \.self) { userId in
                    Button(profilesById[userId]?.displayName ?? "Unavailable participant") {
                        selectedReviewUserId = userId
                        reviewMessage = ""
                        reviewScore = nil
                    }
                }
            } label: {
                HStack {
                    Text(profilesById[selectedReviewUserId ?? userIds[0]]?.displayName ?? "Unavailable participant")
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 42)
            }

            Button {
                moveReviewRecipient(by: 1, userIds: userIds)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.bordered)
        .tint(AppConstants.Colors.accessibleYellow)
    }

    private func submissionPreview(_ submission: AssignmentSubmission, bundle: AssignmentDetailBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Submission Preview", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text(submissionStatusTitle(submission.status))
                    .font(.caption.bold())
                    .foregroundColor(.orange)
            }

            let attachments = bundle.attachments.filter { $0.submissionId == submission.id }
            if attachments.isEmpty {
                Text("Text response only")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
            } else {
                ForEach(attachments) { attachment in
                    Button {
                        openFile(path: attachment.privateFilePath)
                    } label: {
                        Label(attachment.fileName ?? "Attachment", systemImage: "paperclip")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppConstants.Colors.accessibleYellow)
                }
            }
            if submission.structuredPayload.isEmpty == false {
                Divider().overlay(.white.opacity(0.12))
                Text("Structured answers").font(.caption.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
                ForEach(submission.structuredPayload.keys.sorted(), id: \.self) { key in
                    if let value = submission.structuredPayload[key]?.stringValue, value.isEmpty == false {
                        LabeledContent(key.replacingOccurrences(of: "_", with: " ").capitalized, value: value)
                            .font(.caption)
                    }
                }
            }
            if let score = submission.score {
                Label("Score: \(score) / 10", systemImage: "star.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryAction)
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func attemptHistory(_ submissions: [AssignmentSubmission], bundle: AssignmentDetailBundle?) -> some View {
        VStack(spacing: 8) {
            ForEach(submissions) { submission in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Attempt \(submission.attemptNumber ?? fallbackAttemptNumber(submission, in: submissions))")
                            .font(.subheadline.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Spacer()
                        Text(submissionStatusTitle(submission.status))
                            .font(.caption.bold())
                            .foregroundColor(submission.status == "accepted" ? .green : .orange)
                    }
                    if let submittedAt = submission.submittedAt {
                        Text(submittedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.52))
                    }
                    if let score = submission.score {
                        Label("Score: \(score) / 10", systemImage: "star.fill")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.primaryAction)
                    }
                    if canReview, submission.reviewedAt != nil {
                        Button {
                            retroactiveScore = submission.score
                            scoreEditorSubmission = submission
                        } label: {
                            Label(submission.score == nil ? "Add Score" : "Edit Score", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .tint(AppConstants.Colors.accessibleYellow)
                    }
                    if let message = submission.reviewerMessage, message.isEmpty == false {
                        Label(message, systemImage: "text.bubble.fill")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                    }
                    if let bundle {
                        ForEach(bundle.attachments.filter { $0.submissionId == submission.id }) { attachment in
                            Button {
                                openFile(path: attachment.privateFilePath)
                            } label: {
                                Label(attachment.fileName ?? "Attachment", systemImage: "paperclip")
                            }
                            .buttonStyle(.bordered)
                            .tint(AppConstants.Colors.accessibleYellow)
                        }
                        if submission.id != submissions.first?.id {
                            let historicalComments = bundle.feedbackMessages.filter {
                                $0.submissionId == submission.id
                            }
                            if historicalComments.isEmpty == false {
                                Label("Comments", systemImage: "text.bubble")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                                ForEach(historicalComments) { comment in
                                    Text(comment.body)
                                        .font(.caption)
                                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(AppConstants.Colors.background.opacity(0.45))
                .cornerRadius(8)
            }
        }
    }

    private func feedbackSection(
        _ bundle: AssignmentDetailBundle,
        recipientId: UUID,
        title: String
    ) -> some View {
        let messages = bundle.feedbackMessages.filter { message in
            message.recipientId == recipientId
        }
        let conversationEvents = bundle.events.filter { event in
            event.metadata?.recipientId == recipientId
                && ["submitted", "resubmitted", "accepted", "changes_requested", "score_updated"].contains(event.eventType)
        }
        let entries = (
            messages.map(AssignmentConversationEntry.message)
                + conversationEvents.map(AssignmentConversationEntry.event)
        ).sorted { $0.createdAt < $1.createdAt }
        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
            .first ?? 844
        let maximumHeight = AssignmentConversationLayout.maximumHeight(for: screenHeight)
        let viewportHeight = min(maximumHeight, max(100, CGFloat(entries.count) * 88))

        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if entries.isEmpty {
                            Text("No comments yet. Start the conversation before submitting if you have a question.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        } else {
                            ForEach(entries) { entry in
                                switch entry {
                                case .message(let message):
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(profilesById[message.senderId]?.displayName ?? "Unavailable member")
                                                .font(.caption.bold())
                                            Spacer()
                                            if let submissionId = message.submissionId,
                                               let attempt = bundle.submissions.first(where: { $0.id == submissionId })?.attemptNumber {
                                                Text("Attempt \(attempt)")
                                                    .font(.caption2.bold())
                                                    .foregroundColor(AppConstants.Colors.secondaryText)
                                            }
                                        }
                                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                                        Text(message.body)
                                            .font(.subheadline)
                                            .foregroundColor(AppConstants.Colors.primaryText)
                                        if let createdAt = message.createdAt {
                                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundColor(AppConstants.Colors.secondaryText)
                                        }
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(8)
                                    .id(entry.id)
                                case .event(let event):
                                    HStack(spacing: 8) {
                                        Image(systemName: conversationEventIcon(event.eventType))
                                        Text(conversationEventText(event))
                                            .font(.caption.bold())
                                        Spacer()
                                        if let createdAt = event.createdAt {
                                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                        }
                                    }
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(AppConstants.Colors.background.opacity(0.45))
                                    .cornerRadius(8)
                                    .id(entry.id)
                                }
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("conversation-bottom-\(recipientId.uuidString)")
                            .onAppear {
                                conversationAtBottom[recipientId] = true
                                conversationsWithNewMessages.remove(recipientId)
                            }
                            .onDisappear { conversationAtBottom[recipientId] = false }
                    }
                }
                .frame(height: viewportHeight)
                .accessibilityLabel("Assignment conversation")
                .overlay(alignment: .bottomTrailing) {
                    if conversationsWithNewMessages.contains(recipientId) {
                        Button("New messages") {
                            withAnimation { proxy.scrollTo("conversation-bottom-\(recipientId.uuidString)", anchor: .bottom) }
                            conversationsWithNewMessages.remove(recipientId)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppConstants.Colors.accessibleYellow)
                        .padding(8)
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("conversation-bottom-\(recipientId.uuidString)", anchor: .bottom)
                    }
                }
                .onChange(of: entries.count) { oldCount, newCount in
                    guard newCount > oldCount else { return }
                    let currentUserSentLatest: Bool = {
                        guard case .message(let message)? = entries.last else { return false }
                        return message.senderId == currentUserId
                    }()
                    if currentUserSentLatest || conversationAtBottom[recipientId] != false {
                        withAnimation { proxy.scrollTo("conversation-bottom-\(recipientId.uuidString)", anchor: .bottom) }
                    } else {
                        conversationsWithNewMessages.insert(recipientId)
                    }
                }
            }

            if bundle.assignment.status != "closed" && bundle.assignment.status != "archived" {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Add a comment", text: commentBinding(for: recipientId), axis: .vertical)
                        .padding(10)
                        .background(AppConstants.Colors.card)
                        .cornerRadius(8)
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Button {
                        postComment(recipientId: recipientId)
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppConstants.Colors.accessibleYellow)
                    .disabled(isSaving || commentDraft(for: recipientId).isEmpty)
                    .accessibilityLabel("Send comment")
                }
            } else {
                Text("Comments are read-only while this assignment is \(bundle.assignment.status == "archived" ? "archived" : "closed").")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
        }
        .padding()
        .background(AppConstants.Colors.card.opacity(0.55))
        .cornerRadius(8)
    }

    private func recipientActivitySection(_ events: [AssignmentEvent]) -> some View {
        DisclosureGroup(isExpanded: $isActivityExpanded) {
            if events.isEmpty {
                smallPanel("No workflow events recorded yet.")
            } else {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: eventIcon(event.eventType))
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(submissionStatusTitle(event.eventType))
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            HStack(spacing: 4) {
                                if let actorId = event.actorId {
                                    Text(profilesById[actorId]?.displayName ?? "Unavailable participant")
                                }
                                if let createdAt = event.createdAt {
                                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.52))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                }
            }
        } label: {
            HStack {
                Text("My Activity")
                    .font(.headline)
                Spacer()
                Text("\(events.count)")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
        }
        .tint(AppConstants.Colors.accessibleYellow)
        .padding()
        .background(AppConstants.Colors.card.opacity(0.72))
        .cornerRadius(8)
    }

    private func recipientEvents(in bundle: AssignmentDetailBundle) -> [AssignmentEvent] {
        let userId = bundle.capabilities.userId
        let ownSubmissionIds = Set(
            bundle.submissions
                .filter { $0.submittedBy == userId }
                .map(\.id)
        )
        let lifecycleEvents: Set<String> = ["draft", "scheduled", "published", "closed", "archived"]
        return bundle.events.filter { event in
            lifecycleEvents.contains(event.eventType) == false
                && (
                    event.actorId == userId
                    || event.metadata?.recipientId == userId
                    || event.metadata?.submissionId.map(ownSubmissionIds.contains) == true
                )
        }
    }

    private func conversationEventIcon(_ eventType: String) -> String {
        switch eventType {
        case "submitted", "resubmitted": "paperplane.fill"
        case "accepted": "checkmark.seal.fill"
        case "changes_requested": "arrow.uturn.backward.circle.fill"
        case "score_updated": "slider.horizontal.3"
        default: "circle.fill"
        }
    }

    private func conversationEventText(_ event: AssignmentEvent) -> String {
        let attempt = event.metadata?.attemptNumber.map { "Attempt \($0) " } ?? ""
        switch event.eventType {
        case "submitted": return "\(attempt)submitted"
        case "resubmitted": return "\(attempt)resubmitted"
        case "accepted":
            let score = event.metadata?.score.map { " · \($0)/10" } ?? ""
            return "\(attempt)accepted\(score)"
        case "changes_requested":
            return attempt.isEmpty ? "Changes requested" : "Changes requested for \(attempt.lowercased().trimmingCharacters(in: .whitespaces))"
        case "score_updated":
            return event.metadata?.newScore.map { "Score updated to \($0)/10" } ?? "Score cleared"
        default: return event.eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @ViewBuilder
    private func managementHistorySection(_ events: [AssignmentEvent]) -> some View {
        let lifecycleEvents = events.filter {
            ["draft", "scheduled", "published", "closed", "archived"].contains($0.eventType)
        }
        if lifecycleEvents.isEmpty == false {
            DisclosureGroup {
                VStack(spacing: 8) {
                    ForEach(lifecycleEvents) { event in
                        HStack {
                            Label(submissionStatusTitle(event.eventType), systemImage: eventIcon(event.eventType))
                            Spacer()
                            if let createdAt = event.createdAt {
                                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Assignment History")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
            .tint(AppConstants.Colors.accessibleYellow)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
        }
    }

    private func eventIcon(_ eventType: String) -> String {
        switch eventType {
        case "accepted": "checkmark.circle.fill"
        case "changes_requested": "arrow.uturn.backward.circle.fill"
        case "submitted", "resubmitted": "paperplane.fill"
        case "published": "megaphone.fill"
        case "closed": "lock.fill"
        case "archived": "archivebox.fill"
        default: "clock.arrow.circlepath"
        }
    }

    private func smallPanel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
    }

    private func reviewUserIds(_ bundle: AssignmentDetailBundle) -> [UUID] {
        let recipientIds = bundle.recipients.map(\.userId)
        let submissionIds = bundle.submissions.map(\.submittedBy)
        return Array(Set(recipientIds + submissionIds))
            .filter { $0 != bundle.capabilities.userId }
            .sorted { lhs, rhs in
            let left = profilesById[lhs]?.displayName ?? ""
            let right = profilesById[rhs]?.displayName ?? ""
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    private func moveReviewRecipient(by offset: Int, userIds: [UUID]) {
        guard userIds.isEmpty == false else { return }
        let current = selectedReviewUserId ?? userIds[0]
        let currentIndex = userIds.firstIndex(of: current) ?? 0
        let nextIndex = (currentIndex + offset + userIds.count) % userIds.count
        selectedReviewUserId = userIds[nextIndex]
        reviewMessage = ""
        reviewScore = nil
    }

    private func fallbackAttemptNumber(_ submission: AssignmentSubmission, in submissions: [AssignmentSubmission]) -> Int {
        guard let index = submissions.firstIndex(where: { $0.id == submission.id }) else { return 1 }
        return submissions.count - index
    }

    private func submissionStatusTitle(_ status: String) -> String {
        status
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    @MainActor
    private func load() async {
        await model.load(assignmentId: assignmentId)
        if model.didMarkViewedOnLastLoad { onChanged() }
        if let loaded = model.bundle {
            let availableReviewIds = reviewUserIds(loaded)
            if selectedReviewUserId.map(availableReviewIds.contains) != true {
                selectedReviewUserId = availableReviewIds.first
            }
        }
    }

    private func markRead() {
        Task {
            if await model.acknowledge(assignmentId: assignmentId) { onChanged() }
        }
    }

    private func submit(_ assignment: Assignment) {
        Task {
            let saved = await model.submit(
                AssignmentSubmissionDraft(
                    assignment: assignment,
                    fileURLs: selectedFileURLs,
                    feedbackText: feedbackText,
                    idempotencyKey: submissionMutationKey,
                    structuredPayload: structuredSubmissionPayload
                ),
                assignmentId: assignmentId
            )
            if saved {
                selectedFileURLs = []
                feedbackText = ""
                medicationName = ""
                medicationDosage = ""
                medicationInstructions = ""
                medicationRepeatRule = ""
                structuredNotes = ""
                submissionMutationKey = UUID().uuidString
                onChanged()
            }
        }
    }

    private func review(_ submission: AssignmentSubmission, status: String) {
        let mutationKeyId = "\(submission.id.uuidString):\(status)"
        let mutationKey = reviewMutationKeys[mutationKeyId] ?? UUID().uuidString
        reviewMutationKeys[mutationKeyId] = mutationKey
        Task {
            let saved = await model.review(
                AssignmentReviewDraft(
                    submissionId: submission.id,
                    status: status,
                    message: reviewMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reviewMessage,
                    score: reviewScore,
                    idempotencyKey: mutationKey
                ),
                assignmentId: assignmentId
            )
            if saved {
                reviewMessage = ""
                reviewScore = nil
                reviewMutationKeys[mutationKeyId] = nil
                onChanged()
            }
        }
    }

    private func waiveOnboardingRequirement() {
        guard let assignment, assignment.category == .onboarding else { return }
        let reason = waiverReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.isEmpty == false else { return }
        Task {
            if await model.waive(assignmentId: assignment.id, reason: reason) {
                waiverReason = ""
                onChanged()
            }
        }
    }

    private func postComment(recipientId: UUID) {
        let body = commentDraft(for: recipientId)
        guard body.isEmpty == false else { return }
        let mutationKey = commentMutationKeys[recipientId] ?? UUID().uuidString
        commentMutationKeys[recipientId] = mutationKey
        Task {
            let saved = await model.postComment(AssignmentCommentDraft(
                    assignmentId: assignmentId,
                    recipientId: recipientId,
                    body: body,
                    idempotencyKey: mutationKey
                ))
            if saved {
                commentDrafts[recipientId] = ""
                commentMutationKeys[recipientId] = nil
                onChanged()
            }
        }
    }

    private func conversationTitle(for recipientId: UUID, bundle: AssignmentDetailBundle) -> String {
        if recipientId == bundle.capabilities.userId {
            let creatorName = bundle.assignment.assignedBy.flatMap { profilesById[$0]?.displayName }
            return "Conversation with \(creatorName ?? "assignment creator")"
        }
        return "Conversation with \(profilesById[recipientId]?.displayName ?? "recipient")"
    }

    private func updateScore(for submission: AssignmentSubmission) {
        let mutationKey = UUID().uuidString
        Task {
            let saved = await model.updateScore(
                AssignmentScoreUpdate(
                    submissionId: submission.id,
                    score: retroactiveScore,
                    idempotencyKey: mutationKey
                ),
                assignmentId: assignmentId
            )
            if saved {
                scoreEditorSubmission = nil
                onChanged()
            }
        }
    }

    private func commentDraft(for submissionId: UUID) -> String {
        (commentDrafts[submissionId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commentBinding(for submissionId: UUID) -> Binding<String> {
        Binding(
            get: { commentDrafts[submissionId] ?? "" },
            set: { commentDrafts[submissionId] = $0 }
        )
    }

    private func changeStatus(to status: String) {
        Task {
            if await model.setStatus(assignmentId: assignmentId, status: status) { onChanged() }
        }
    }

    private func materialIcon(_ material: AssignmentMaterial) -> String {
        switch material.materialType {
        case "article": "doc.text.fill"
        case "link": "link"
        case "image": "photo.fill"
        case "video": "video.fill"
        default: "paperclip"
        }
    }

    private func openFile(path: String?) {
        guard let path else { return }
        Task {
            if let localURL = await model.previewURL(
                path: path,
                preferredName: URL(fileURLWithPath: path).lastPathComponent
            ) {
                previewURL = localURL
            }
        }
    }

    private func openLink(_ value: String) {
        guard let url = URL(string: value) else { return }
        webURL = url
    }

    private func previewFile(_ material: AssignmentMaterial) {
        guard let path = material.privateFilePath else { return }
        Task {
            if let localURL = await model.previewURL(
                path: path,
                preferredName: material.fileName ?? URL(fileURLWithPath: path).lastPathComponent
            ) {
                previewURL = localURL
            }
        }
    }

}
