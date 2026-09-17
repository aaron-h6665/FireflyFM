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
    @Test @MainActor func onlyDirectorHasTwoResponsibilities() {
        let session = AppSessionManager()
        #expect(!session.workspaceCanManage)
        #expect(!session.workspaceManaging(.manage))
    }
}
