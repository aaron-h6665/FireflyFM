import Foundation
import Observation

@MainActor
@Observable
final class PaymentsModel {
    private let client: PaymentsClient

    private(set) var account: SchoolPaymentAccount?
    private(set) var invoices: [BillingInvoice] = []
    private(set) var payments: [BillingPayment] = []
    private(set) var parents: [SchoolMember] = []
    private(set) var children: [Child] = []
    private(set) var schools: [School] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?
    private(set) var isMutating = false

    init(client: PaymentsClient? = nil) {
        self.client = client ?? .live
    }

    var outstandingCents: Int64 {
        invoices.filter { $0.status == .open }.reduce(0) { $0 + $1.amountRemainingCents }
    }

    var collectedCents: Int64 {
        invoices.reduce(0) { $0 + $1.amountPaidCents }
    }

    var overdueCount: Int { invoices.filter(\.isPastDue).count }

    func load(schoolId: UUID?, policy: PaymentAccessPolicy) async {
        phase = .loading
        errorMessage = nil
        do {
            async let loadedInvoices = client.fetchInvoices(policy.hasCrossSchoolScope ? nil : schoolId)
            async let loadedPayments = client.fetchPayments(policy.hasCrossSchoolScope ? nil : schoolId)
            async let loadedSchools: [School] = policy.hasCrossSchoolScope ? client.fetchSchools() : []
            invoices = try await loadedInvoices
            payments = try await loadedPayments
            schools = try await loadedSchools
            if policy.canManage, let schoolId {
                account = try await client.fetchAccount(schoolId)
                async let loadedParents = client.fetchParents(schoolId)
                async let loadedChildren = client.fetchChildren(schoolId)
                parents = try await loadedParents
                children = try await loadedChildren
            } else {
                account = nil
                parents = []
                children = []
            }
            phase = invoices.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            phase = .idle
        } catch {
            errorMessage = AppErrorMessage.school("Could not load billing", error)
            phase = .failed(errorMessage ?? "Could not load billing")
        }
    }

    func createInvoice(_ draft: BillingInvoiceDraft, policy: PaymentAccessPolicy) async -> Bool {
        guard policy.canManage else { return false }
        return await mutate {
            _ = try await client.createInvoice(draft)
        }
    }

    func perform(_ action: String, invoice: BillingInvoice, policy: PaymentAccessPolicy) async -> Bool {
        guard policy.canManage else { return false }
        return await mutate {
            _ = try await client.performAction(invoice.id, action)
        }
    }

    func onboardingURL(schoolId: UUID, policy: PaymentAccessPolicy) async -> URL? {
        guard policy.canManage else { return nil }
        var result: URL?
        let succeeded = await mutate { result = try await client.createOnboardingLink(schoolId) }
        return succeeded ? result : nil
    }

    func documentURL(invoice: BillingInvoice, kind: String, policy: PaymentAccessPolicy) async -> URL? {
        guard policy.canPay(invoice: invoice) else { return nil }
        var result: URL?
        let succeeded = await mutate { result = try await client.fetchDocumentLink(invoice.id, kind) }
        return succeeded ? result : nil
    }

    func items(for invoiceId: UUID) async throws -> [BillingInvoiceItem] {
        try await client.fetchItems(invoiceId)
    }

    private func mutate(_ operation: () async throws -> Void) async -> Bool {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Billing request failed", error)
            return false
        }
    }
}
