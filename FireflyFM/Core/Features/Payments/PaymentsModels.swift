import Foundation

enum BillingInvoiceStatus: String, Codable, CaseIterable, Hashable {
    case draft
    case open
    case paid
    case void
    case uncollectible

    var title: String {
        switch self {
        case .draft: "Draft"
        case .open: "Open"
        case .paid: "Paid"
        case .void: "Void"
        case .uncollectible: "Uncollectible"
        }
    }
}

enum BillingPaymentStatus: String, Codable, CaseIterable, Hashable {
    case pending
    case processing
    case succeeded
    case failed
    case refunded
    case disputed

    var title: String { rawValue.capitalized }
}

enum BillingRecurrence: String, Codable, CaseIterable, Identifiable, Hashable {
    case once
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: "One time"
        case .weekly: "Weekly"
        case .biweekly: "Every two weeks"
        case .monthly: "Monthly"
        }
    }
}

struct SchoolPaymentAccount: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var status: String
    var detailsSubmitted: Bool
    var chargesEnabled: Bool
    var payoutsEnabled: Bool
    var sandbox: Bool
    var livePaymentsEnabled: Bool
    var requirementsDueCount: Int
    var updatedAt: Date?

    var isReady: Bool { status == "ready" && chargesEnabled && payoutsEnabled }

    enum CodingKeys: String, CodingKey {
        case id, status, sandbox
        case schoolId = "school_id"
        case detailsSubmitted = "details_submitted"
        case chargesEnabled = "charges_enabled"
        case payoutsEnabled = "payouts_enabled"
        case livePaymentsEnabled = "live_payments_enabled"
        case requirementsDueCount = "requirements_due_count"
        case updatedAt = "updated_at"
    }
}

struct BillingInvoice: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var parentUserId: UUID
    var childId: UUID?
    var scheduleId: UUID?
    var invoiceNumber: String?
    var description: String
    var currency: String
    var amountDueCents: Int64
    var amountPaidCents: Int64
    var amountRemainingCents: Int64
    var status: BillingInvoiceStatus
    var paymentStatus: BillingPaymentStatus
    var dueAt: Date?
    var sentAt: Date?
    var paidAt: Date?
    var voidedAt: Date?
    var lastSyncedAt: Date?
    var createdAt: Date?

    var isPastDue: Bool {
        status == .open && (dueAt.map { $0 < Date() } == true)
    }

    var displayStatus: String {
        if isPastDue { return "Past Due" }
        if paymentStatus == .processing { return "Processing" }
        if [.refunded, .disputed].contains(paymentStatus) { return paymentStatus.title }
        return status.title
    }

    enum CodingKeys: String, CodingKey {
        case id, description, currency, status
        case schoolId = "school_id"
        case parentUserId = "parent_user_id"
        case childId = "child_id"
        case scheduleId = "schedule_id"
        case invoiceNumber = "invoice_number"
        case amountDueCents = "amount_due_cents"
        case amountPaidCents = "amount_paid_cents"
        case amountRemainingCents = "amount_remaining_cents"
        case paymentStatus = "payment_status"
        case dueAt = "due_at"
        case sentAt = "sent_at"
        case paidAt = "paid_at"
        case voidedAt = "voided_at"
        case lastSyncedAt = "last_synced_at"
        case createdAt = "created_at"
    }
}

struct BillingInvoiceItem: Codable, Identifiable, Hashable {
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

struct BillingPayment: Codable, Identifiable, Hashable {
    var id: UUID
    var invoiceId: UUID?
    var schoolId: UUID
    var parentUserId: UUID
    var amountCents: Int64
    var currency: String
    var status: BillingPaymentStatus
    var paymentMethodType: String?
    var failureCode: String?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, currency, status
        case invoiceId = "invoice_id"
        case schoolId = "school_id"
        case parentUserId = "parent_user_id"
        case amountCents = "amount_cents"
        case paymentMethodType = "payment_method_type"
        case failureCode = "failure_code"
        case updatedAt = "updated_at"
    }
}

struct BillingLineItemDraft: Codable, Hashable {
    var description: String
    var quantity: Int
    var unitAmountCents: Int
}

struct BillingInvoiceDraft: Codable, Hashable {
    var schoolId: UUID
    var parentUserId: UUID
    var childId: UUID?
    var lineItems: [BillingLineItemDraft]
    var dueDate: Date
    var recurrence: BillingRecurrence
    var memo: String?
    var idempotencyKey: String
}

struct BillingMutationResponse: Codable, Hashable {
    var invoiceId: UUID?
    var status: String
}

struct BillingLinkResponse: Codable, Hashable {
    var url: URL
    var expiresAt: Date?
}

enum BillingMoney {
    static func string(cents: Int64, currency: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
    }
}
