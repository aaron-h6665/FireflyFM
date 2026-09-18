import Foundation
import Testing
@testable import FireflyFM

struct WorkspaceBetaTests {
    @Test func requestedChangesStayActionableInsteadOfArchived() {
        #expect(WorkspaceBucket.paperwork(status: "changes_requested", managing: false) == .attention)
        #expect(WorkspaceBucket.paperwork(status: "changes_requested", managing: true) == .waiting)
        #expect(WorkspaceBucket.paperwork(status: "pending_review", managing: true) == .attention)
        #expect(WorkspaceBucket.paperwork(status: "pending_review", managing: false) == .waiting)
        #expect(WorkspaceBucket.paperwork(status: "accepted", managing: false) == .history)
    }
    @Test func teachersHaveNoManagementCapabilities() {
        let context = AppAccessContext(role: .teacher)
        #expect(!AssignmentAccessPolicy(context: context).canCreate)
        #expect(!AssignmentAccessPolicy(context: context).canReview)
        #expect(!PaperworkAccessPolicy(context: context).canCreate)
        #expect(!PaymentAccessPolicy(context: context).canManage)
    }
    @Test func onboardingDirectorCannotManage() {
        let context = AppAccessContext(role: .schoolDirector, accessState: "onboarding")
        #expect(!AssignmentAccessPolicy(context: context).canCreate)
        #expect(!PaperworkAccessPolicy(context: context).canReview)
        #expect(!PaymentAccessPolicy(context: context).canManageRecipientInstructions)
    }
    @Test func paymentsSeparateWaitingFromCompleted() {
        #expect(WorkspaceBucket.payment(.paymentSubmitted, managing: false) == .waiting)
        #expect(WorkspaceBucket.payment(.paymentSubmitted, managing: true) == .attention)
        #expect(WorkspaceBucket.payment(.rejected, managing: false) == .attention)
        #expect(WorkspaceBucket.payment(.void, managing: false) == .history)
        #expect(WorkspaceBucket.history.title(managing: false) == "Done")
        #expect(WorkspaceBucket.history.title(managing: true) == "Done")
    }
    @Test func unansweredQuestionsRemainAvailableForCorrections() {
        let rows = GoogleFormAnswerPresentation.rows(payload: [:], questions: [
            .init(id: "phone", title: "Phone number", fieldKey: nil),
            .init(id: "reference", title: "Reference", fieldKey: "submission_reference")
        ])
        #expect(rows.count == 1)
        #expect(rows.first?.id == "phone")
        #expect(rows.first?.value == "Not provided")
    }
    @Test func workspaceNotificationsOpenExactRecords() throws {
        let schoolId = UUID()
        let paperworkId = UUID()
        let formId = UUID()
        let paperworkJSON = """
        {
          "id": "\(UUID())", "school_id": "\(schoolId)", "school_name": "Beta School",
          "title": "Paperwork changes requested", "body": "Update the marked fields.",
          "category": "paperwork_reviewed", "source_type": "paperwork_submission", "source_id": "\(paperworkId)"
        }
        """.data(using: .utf8)!
        let formJSON = """
        {
          "id": "\(UUID())", "school_id": "\(schoolId)", "school_name": "Beta School",
          "title": "Form changes requested", "body": "Update the marked answers.",
          "category": "google_form_response", "source_type": "google_form_import", "source_id": "\(formId)"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let paperwork = try decoder.decode(NotificationInboxItem.self, from: paperworkJSON)
        let form = try decoder.decode(NotificationInboxItem.self, from: formJSON)

        #expect(NotificationDestinationResolver().resolve(paperwork) == .paperworkRecord(
            paperworkId,
            sourceType: "paperwork_submission",
            schoolId: schoolId
        ))
        #expect(NotificationDestinationResolver().resolve(form) == .paperworkRecord(
            formId,
            sourceType: "google_form_import",
            schoolId: schoolId
        ))
    }
    @Test @MainActor func onlyDirectorHasTwoResponsibilities() {
        let session = AppSessionManager()
        #expect(!session.workspaceCanManage)
        #expect(!session.workspaceManaging(.manage))
    }
}
