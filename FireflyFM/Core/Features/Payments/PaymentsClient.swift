import Foundation
import Supabase

struct PaymentsClient {
    var fetchAccount: (UUID) async throws -> SchoolPaymentAccount?
    var fetchInvoices: (UUID?) async throws -> [BillingInvoice]
    var fetchItems: (UUID) async throws -> [BillingInvoiceItem]
    var fetchPayments: (UUID?) async throws -> [BillingPayment]
    var fetchParents: (UUID) async throws -> [SchoolMember]
    var fetchChildren: (UUID) async throws -> [Child]
    var fetchSchools: () async throws -> [School]
    var createInvoice: (BillingInvoiceDraft) async throws -> BillingMutationResponse
    var performAction: (UUID, String) async throws -> BillingMutationResponse
    var createOnboardingLink: (UUID) async throws -> URL
    var fetchDocumentLink: (UUID, String) async throws -> URL

    static let live = PaymentsClient(
        fetchAccount: { schoolId in
            let rows: [SchoolPaymentAccount] = try await AppConstants.supabase
                .from("school_payment_accounts")
                .select()
                .eq("school_id", value: schoolId)
                .limit(1)
                .execute()
                .value
            return rows.first
        },
        fetchInvoices: { schoolId in
            var query = AppConstants.supabase.from("billing_invoices").select()
            if let schoolId { query = query.eq("school_id", value: schoolId) }
            return try await query
                .order("due_at", ascending: false, nullsFirst: false)
                .execute()
                .value
        },
        fetchItems: { invoiceId in
            try await AppConstants.supabase.from("billing_invoice_items")
                .select()
                .eq("invoice_id", value: invoiceId)
                .order("created_at", ascending: true)
                .execute()
                .value
        },
        fetchPayments: { schoolId in
            var query = AppConstants.supabase.from("billing_payments").select()
            if let schoolId { query = query.eq("school_id", value: schoolId) }
            return try await query
                .order("updated_at", ascending: false)
                .execute()
                .value
        },
        fetchParents: { try await SchoolService.shared.fetchMembers(schoolId: $0, role: .parent) },
        fetchChildren: { try await SchoolWorkflowService.shared.fetchChildren(schoolId: $0) },
        fetchSchools: { try await SchoolService.shared.fetchSchoolsForHQ() },
        createInvoice: { draft in
            try await invoke("billing-create-invoice", body: draft)
        },
        performAction: { invoiceId, action in
            try await invoke(
                "billing-invoice-action",
                body: BillingActionRequest(
                    invoiceId: invoiceId,
                    action: action,
                    idempotencyKey: "ios:\(action):\(UUID().uuidString)"
                )
            )
        },
        createOnboardingLink: { schoolId in
            let response: BillingLinkResponse = try await invoke(
                "stripe-connect-onboard",
                body: BillingSchoolRequest(schoolId: schoolId)
            )
            return response.url
        },
        fetchDocumentLink: { invoiceId, kind in
            let response: BillingLinkResponse = try await invoke(
                "billing-document-link",
                body: BillingDocumentRequest(invoiceId: invoiceId, kind: kind)
            )
            return response.url
        }
    )
}

private struct BillingSchoolRequest: Encodable {
    let schoolId: UUID
}

private struct BillingActionRequest: Encodable {
    let invoiceId: UUID
    let action: String
    let idempotencyKey: String
}

private struct BillingDocumentRequest: Encodable {
    let invoiceId: UUID
    let kind: String
}

private func invoke<Response: Decodable, Body: Encodable>(
    _ function: String,
    body: Body
) async throws -> Response {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try await AppConstants.supabase.functions.invoke(
        function,
        options: FunctionInvokeOptions(body: body, encoder: encoder),
        decoder: decoder
    )
}
