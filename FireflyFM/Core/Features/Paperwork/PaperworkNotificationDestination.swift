import SwiftUI
import Supabase

/// Resolve the notification's original record, not the current list's first row.
struct PaperworkNotificationDestination: View {
    @EnvironmentObject private var appSession: AppSessionManager
    let recordId: UUID
    let sourceType: String
    let schoolId: UUID
    @State private var item: PaperworkItem?
    @State private var recipients: [PaperworkItem] = []
    @State private var names: [UUID: String] = [:]
    @State private var school: School?
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        Group {
            if let item {
                PaperworkBetaDestination(item: item, school: school,
                    reviewing: appSession.workspaceCanManage && item.recipientId != appSession.profile?.id, onChanged: {})
            } else if !recipients.isEmpty {
                PaperworkRecipientList(items: recipients, names: names, school: school, onChanged: {})
            } else if loading { ProgressView("Loading paperwork…") }
            else { ContentUnavailableView("Paperwork unavailable", systemImage: "doc.text", description: Text(error ?? "This record is no longer available to your account.")) }
        }.task { await load() }
    }
    private func load() async {
        defer { loading = false }
        do {
            let schools: [School] = try await AppConstants.supabase.from("schools").select().eq("id", value: schoolId).execute().value
            school = schools.first
            if sourceType == "google_form_import" || sourceType == "google_form_response" {
                let imports: [GoogleFormImport] = try await AppConstants.supabase.from("google_form_imports").select().eq("id", value: recordId).execute().value
                guard let response = imports.first else { return }
                item = PaperworkItem(itemId: response.id, schoolId: response.schoolId, sourceKind: .googleForm,
                    title: "Form response", description: nil, childId: response.childId,
                    recipientId: response.submittedBy ?? response.id, status: response.status, dueAt: nil,
                    onboardingRequirementInstanceId: nil, googleFormConnectionId: response.connectionId,
                    googleFormImportId: response.id, nativeRequestId: nil)
            } else {
                var requestId = recordId
                var recipientId = appSession.profile?.id
                if sourceType == "paperwork_submission" {
                    let submissions: [PaperworkSubmission] = try await AppConstants.supabase.from("paperwork_submissions").select().eq("id", value: recordId).execute().value
                    guard let submission = submissions.first else { return }
                    requestId = submission.assignmentId; recipientId = submission.submittedBy
                }
                struct Params: Encodable { let input_school_id: UUID; let input_archived: Bool }
                async let active: [PaperworkItem] = AppConstants.supabase.rpc("fetch_my_paperwork_items_v2", params: Params(input_school_id: schoolId, input_archived: false)).execute().value
                async let history: [PaperworkItem] = AppConstants.supabase.rpc("fetch_my_paperwork_items_v2", params: Params(input_school_id: schoolId, input_archived: true)).execute().value
                let candidates = try await (active + history).filter { $0.nativeRequestId == requestId }
                item = candidates.first { $0.recipientId == recipientId }
                if item == nil && appSession.workspaceCanManage {
                    recipients = candidates
                    struct LabelParams: Encodable { let input_school_id: UUID }
                    let labels: [WorkspacePersonLabel] = try await AppConstants.supabase.rpc("fetch_workspace_recipient_labels", params: LabelParams(input_school_id: schoolId)).execute().value
                    names = Dictionary(labels.map { ($0.user_id, $0.display_name) }, uniquingKeysWith: { first, _ in first })
                }
            }
        } catch { self.error = AppErrorMessage.school("Could not load paperwork", error) }
    }
}
