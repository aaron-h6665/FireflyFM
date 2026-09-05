import Foundation
import Supabase

struct PaymentsClient {
    var fetchProfile: (UUID) async throws -> SchoolZelleProfile?
    var fetchInvoices: (UUID?) async throws -> [ZelleInvoice]
    var fetchInvoice: (UUID) async throws -> ZelleInvoice?
    var fetchItems: (UUID) async throws -> [ZelleInvoiceItem]
    var fetchSubmissions: (UUID) async throws -> [ZellePaymentSubmission]
    var fetchParents: (UUID) async throws -> [SchoolMember]
    var fetchChildren: (UUID) async throws -> [Child]
    var fetchSchools: () async throws -> [School]
    var saveProfile: (ZelleProfileDraft) async throws -> SchoolZelleProfile
    var createInvoice: (ZelleInvoiceDraft) async throws -> ZelleInvoice
    var submitPayment: (ZellePaymentSubmissionDraft) async throws -> ZellePaymentSubmission
    var reviewPayment: (UUID, String, String?) async throws -> ZelleInvoice
    var voidInvoice: (UUID, String) async throws -> ZelleInvoice

    static let live = PaymentsClient(
        fetchProfile: { schoolId in
            let rows: [SchoolZelleProfile] = try await AppConstants.supabase
                .from("school_zelle_profiles")
                .select()
                .eq("school_id", value: schoolId)
                .limit(1)
                .execute()
                .value
            return rows.first
        },
        fetchInvoices: { schoolId in
            var query = AppConstants.supabase.from("zelle_invoices").select()
            if let schoolId { query = query.eq("school_id", value: schoolId) }
            return try await query
                .order("due_at", ascending: false, nullsFirst: false)
                .execute()
                .value
        },
        fetchInvoice: { invoiceId in
            let rows: [ZelleInvoice] = try await AppConstants.supabase
                .from("zelle_invoices")
                .select()
                .eq("id", value: invoiceId)
                .limit(1)
                .execute()
                .value
            return rows.first
        },
        fetchItems: { invoiceId in
            try await AppConstants.supabase.from("zelle_invoice_items")
                .select()
                .eq("invoice_id", value: invoiceId)
                .order("created_at", ascending: true)
                .execute()
                .value
        },
        fetchSubmissions: { invoiceId in
            try await AppConstants.supabase.from("zelle_payment_submissions")
                .select()
                .eq("invoice_id", value: invoiceId)
                .order("created_at", ascending: false)
                .execute()
                .value
        },
        fetchParents: { try await SchoolService.shared.fetchMembers(schoolId: $0, role: .parent) },
        fetchChildren: { try await SchoolWorkflowService.shared.fetchChildren(schoolId: $0) },
        fetchSchools: { try await SchoolService.shared.fetchSchoolsForHQ() },
        saveProfile: { draft in
            let rows: [SchoolZelleProfile] = try await AppConstants.supabase.rpc(
                "save_school_zelle_profile",
                params: SaveZelleProfileParams(draft: draft)
            )
            .execute()
            .value
            guard let profile = rows.first else { throw SchoolWorkflowError.notFound }
            return profile
        },
        createInvoice: { draft in
            let rows: [ZelleInvoice] = try await AppConstants.supabase.rpc(
                "issue_zelle_invoice",
                params: IssueZelleInvoiceParams(draft: draft)
            )
            .execute()
            .value
            guard let invoice = rows.first else { throw SchoolWorkflowError.notFound }
            return invoice
        },
        submitPayment: { draft in
            let rows: [ZellePaymentSubmission] = try await AppConstants.supabase.rpc(
                "submit_zelle_payment",
                params: SubmitZellePaymentParams(draft: draft)
            )
            .execute()
            .value
            guard let submission = rows.first else { throw SchoolWorkflowError.notFound }
            return submission
        },
        reviewPayment: { submissionId, decision, note in
            let rows: [ZelleInvoice] = try await AppConstants.supabase.rpc(
                "review_zelle_payment",
                params: ReviewZellePaymentParams(submissionId: submissionId, decision: decision, note: note)
            )
            .execute()
            .value
            guard let invoice = rows.first else { throw SchoolWorkflowError.notFound }
            return invoice
        },
        voidInvoice: { invoiceId, reason in
            let rows: [ZelleInvoice] = try await AppConstants.supabase.rpc(
                "void_zelle_invoice",
                params: VoidZelleInvoiceParams(invoiceId: invoiceId, reason: reason)
            )
            .execute()
            .value
            guard let invoice = rows.first else { throw SchoolWorkflowError.notFound }
            return invoice
        }
    )
}

private struct SaveZelleProfileParams: Encodable {
    let schoolId: UUID
    let recipientDisplayName: String
    let recipientType: String
    let recipientValue: String
    let memoPrefix: String
    let paymentInstructions: String?
    let active: Bool
    let betaSimulationEnabled: Bool

    init(draft: ZelleProfileDraft) {
        schoolId = draft.schoolId
        recipientDisplayName = draft.recipientDisplayName
        recipientType = draft.recipientType.rawValue
        recipientValue = draft.recipientValue
        memoPrefix = draft.memoPrefix
        paymentInstructions = draft.paymentInstructions
        active = draft.active
        betaSimulationEnabled = draft.betaSimulationEnabled
    }

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case recipientDisplayName = "input_recipient_display_name"
        case recipientType = "input_recipient_type"
        case recipientValue = "input_recipient_value"
        case memoPrefix = "input_memo_prefix"
        case paymentInstructions = "input_payment_instructions"
        case active = "input_active"
        case betaSimulationEnabled = "input_beta_simulation_enabled"
    }
}

private struct IssueZelleInvoiceParams: Encodable {
    let schoolId: UUID
    let payerUserId: UUID
    let childId: UUID?
    let description: String
    let dueAt: Date?
    let items: [ZelleInvoiceItemDraft]
    let idempotencyKey: String

    init(draft: ZelleInvoiceDraft) {
        schoolId = draft.schoolId
        payerUserId = draft.payerUserId
        childId = draft.childId
        description = draft.description
        dueAt = draft.dueAt
        items = draft.items
        idempotencyKey = draft.idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case payerUserId = "input_payer_user_id"
        case childId = "input_child_id"
        case description = "input_description"
        case dueAt = "input_due_at"
        case items = "input_items"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct SubmitZellePaymentParams: Encodable {
    let invoiceId: UUID
    let amountCents: Int64
    let sentAt: Date
    let confirmationReference: String
    let idempotencyKey: String

    init(draft: ZellePaymentSubmissionDraft) {
        invoiceId = draft.invoiceId
        amountCents = draft.amountCents
        sentAt = draft.sentAt
        confirmationReference = draft.confirmationReference
        idempotencyKey = draft.idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case invoiceId = "input_invoice_id"
        case amountCents = "input_amount_cents"
        case sentAt = "input_sent_at"
        case confirmationReference = "input_confirmation_reference"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct ReviewZellePaymentParams: Encodable {
    let submissionId: UUID
    let decision: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case submissionId = "input_submission_id"
        case decision = "input_decision"
        case note = "input_reviewer_note"
    }
}

private struct VoidZelleInvoiceParams: Encodable {
    let invoiceId: UUID
    let reason: String

    enum CodingKeys: String, CodingKey {
        case invoiceId = "input_invoice_id"
        case reason = "input_reason"
    }
}

private extension ZelleInvoiceItemDraft {
    enum CodingKeys: String, CodingKey {
        case description
        case quantity
        case unitAmountCents = "unit_amount_cents"
    }
}
