import Foundation

enum ZelleInvoiceStatus: String, Codable, CaseIterable, Hashable {
    case draft
    case open
    case paymentSubmitted = "payment_submitted"
    case underReview = "under_review"
    case paid
    case rejected
    case void
    case expired

    var title: String {
        switch self {
        case .draft: "Draft"
        case .open: "Ready to pay"
        case .paymentSubmitted: "Submitted"
        case .underReview: "Under review"
        case .paid: "Paid"
        case .rejected: "Update requested"
        case .void: "Voided"
        case .expired: "Expired"
        }
    }
}

enum ZellePaymentSubmissionStatus: String, Codable, CaseIterable, Hashable {
    case submitted
    case underReview = "under_review"
    case approved
    case rejected

    var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum ZelleRecipientType: String, Codable, CaseIterable, Identifiable, Hashable {
    case email
    case mobile

    var id: String { rawValue }
    var title: String { self == .email ? "Email address" : "Mobile number" }
}

struct SchoolZelleProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var recipientDisplayName: String
    var recipientType: ZelleRecipientType
    var recipientValue: String
    var memoPrefix: String
    var paymentInstructions: String?
    var active: Bool
    var betaSimulationEnabled: Bool
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, active
        case schoolId = "school_id"
        case recipientDisplayName = "recipient_display_name"
        case recipientType = "recipient_type"
        case recipientValue = "recipient_value"
        case memoPrefix = "memo_prefix"
        case paymentInstructions = "payment_instructions"
        case betaSimulationEnabled = "beta_simulation_enabled"
        case updatedAt = "updated_at"
    }
}

struct ZelleInvoice: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var payerUserId: UUID
    var payerRole: SchoolRole
    var childId: UUID?
    var onboardingRequirementInstanceId: UUID?
    var invoiceNumber: String
    var description: String
    var currency: String
    var amountDueCents: Int64
    var amountPaidCents: Int64
    var status: ZelleInvoiceStatus
    var dueAt: Date?
    var issuedAt: Date?
    var paidAt: Date?
    var voidedAt: Date?
    var createdAt: Date?

    var amountRemainingCents: Int64 { max(0, amountDueCents - amountPaidCents) }
    var isOnboardingInvoice: Bool { onboardingRequirementInstanceId != nil }
    var isPastDue: Bool {
        [.open, .rejected].contains(status) && (dueAt.map { $0 < Date() } == true)
    }

    var displayStatus: String { isPastDue ? "Past due" : status.title }

    enum CodingKeys: String, CodingKey {
        case id, description, currency, status
        case schoolId = "school_id"
        case payerUserId = "payer_user_id"
        case payerRole = "payer_role"
        case childId = "child_id"
        case onboardingRequirementInstanceId = "onboarding_requirement_instance_id"
        case invoiceNumber = "invoice_number"
        case amountDueCents = "amount_due_cents"
        case amountPaidCents = "amount_paid_cents"
        case dueAt = "due_at"
        case issuedAt = "issued_at"
        case paidAt = "paid_at"
        case voidedAt = "voided_at"
        case createdAt = "created_at"
    }
}

struct ZelleInvoiceItem: Codable, Identifiable, Hashable {
    var id: UUID
    var invoiceId: UUID
    var description: String
    var quantity: Int
    var unitAmountCents: Int64
    var amountCents: Int64

    enum CodingKeys: String, CodingKey {
        case id, description, quantity
        case invoiceId = "invoice_id"
        case unitAmountCents = "unit_amount_cents"
        case amountCents = "amount_cents"
    }
}

struct ZellePaymentSubmission: Codable, Identifiable, Hashable {
    var id: UUID
    var invoiceId: UUID
    var schoolId: UUID
    var payerUserId: UUID
    var amountCents: Int64
    var sentAt: Date
    var confirmationReference: String
    var status: ZellePaymentSubmissionStatus
    var reviewerNote: String?
    var reviewedBy: UUID?
    var reviewedAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case invoiceId = "invoice_id"
        case schoolId = "school_id"
        case payerUserId = "payer_user_id"
        case amountCents = "amount_cents"
        case sentAt = "sent_at"
        case confirmationReference = "confirmation_reference"
        case reviewerNote = "reviewer_note"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
    }
}

struct ZelleInvoiceItemDraft: Codable, Hashable {
    var description: String
    var quantity: Int
    var unitAmountCents: Int
}

struct ZelleInvoiceDraft: Codable, Hashable {
    var schoolId: UUID
    var payerUserId: UUID
    var childId: UUID?
    var description: String
    var dueAt: Date?
    var items: [ZelleInvoiceItemDraft]
    var idempotencyKey: String
}

struct ZellePaymentSubmissionDraft: Hashable {
    var invoiceId: UUID
    var amountCents: Int64
    var sentAt: Date
    var confirmationReference: String
    var idempotencyKey: String
}

struct ZelleProfileDraft: Hashable {
    var schoolId: UUID
    var recipientDisplayName: String
    var recipientType: ZelleRecipientType
    var recipientValue: String
    var memoPrefix: String
    var paymentInstructions: String?
    var active: Bool
    var betaSimulationEnabled: Bool
}

enum BillingMoney {
    static func string(cents: Int64, currency: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
    }
}
