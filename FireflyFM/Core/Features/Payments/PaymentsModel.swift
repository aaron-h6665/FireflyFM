import Foundation
import Observation

@MainActor
@Observable
final class PaymentsModel {
    private let client: PaymentsClient

    private(set) var profile: SchoolZelleProfile?
    private(set) var invoices: [ZelleInvoice] = []
    private(set) var items: [ZelleInvoiceItem] = []
    private(set) var submissions: [ZellePaymentSubmission] = []
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
        invoices.filter { [.open, .paymentSubmitted, .underReview, .rejected].contains($0.status) }
            .reduce(0) { $0 + $1.amountRemainingCents }
    }

    var collectedCents: Int64 { invoices.reduce(0) { $0 + $1.amountPaidCents } }
    var overdueCount: Int { invoices.filter(\.isPastDue).count }

    func feeSummaries() -> [SchoolFeeSummary] {
        schools.map { school in
            let schoolInvoices = invoices.filter { $0.schoolId == school.id }
            let collected = schoolInvoices.reduce(0) { $0 + $1.amountPaidCents }
            let outstanding = schoolInvoices
                .filter { [.open, .paymentSubmitted, .underReview, .rejected].contains($0.status) }
                .reduce(0) { $0 + $1.amountRemainingCents }
            let paid = schoolInvoices.filter { $0.status == .paid }.count
            let open = schoolInvoices.filter { [.open, .paymentSubmitted, .underReview, .rejected].contains($0.status) }.count
            let overdue = schoolInvoices.filter(\.isPastDue).count
            return SchoolFeeSummary(
                school: school,
                collectedCents: collected,
                outstandingCents: outstanding,
                paidCount: paid,
                openCount: open,
                overdueCount: overdue,
                totalInvoices: schoolInvoices.count
            )
        }
        .sorted { $0.collectedCents > $1.collectedCents }
    }

    func invoices(for schoolId: UUID?) -> [ZelleInvoice] {
        guard let schoolId else { return invoices }
        return invoices.filter { $0.schoolId == schoolId }
    }

    func outstandingCents(for schoolId: UUID?) -> Int64 {
        invoices(for: schoolId)
            .filter { [.open, .paymentSubmitted, .underReview, .rejected].contains($0.status) }
            .reduce(0) { $0 + $1.amountRemainingCents }
    }

    func collectedCents(for schoolId: UUID?) -> Int64 {
        invoices(for: schoolId).reduce(0) { $0 + $1.amountPaidCents }
    }

    func overdueCount(for schoolId: UUID?) -> Int {
        invoices(for: schoolId).filter(\.isPastDue).count
    }

    func loadSchoolData(schoolId: UUID) async {
        do {
            async let loadedProfile = client.fetchProfile(schoolId)
            async let loadedParents = client.fetchParents(schoolId)
            async let loadedChildren = AppConfiguration.workspaceBetaEnabled ? [] : client.fetchChildren(schoolId)
            profile = try await loadedProfile
            parents = try await loadedParents
            children = try await loadedChildren
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not load school billing details", error)
        }
    }

    /// Used from an HQ school's enrollment setup. It intentionally does not
    /// load cross-school invoices, parents, or children just to edit the
    /// recipient instructions needed before a director payment requirement is
    /// published.
    func loadProfile(schoolId: UUID, policy: PaymentAccessPolicy) async {
        guard policy.canManageRecipientInstructions else { return }
        errorMessage = nil
        do {
            profile = try await client.fetchProfile(schoolId)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load Zelle settings", error)
        }
    }

    func load(schoolId: UUID?, policy: PaymentAccessPolicy) async {
        phase = .loading
        errorMessage = nil
        do {
            async let loadedInvoices = client.fetchInvoices(policy.hasCrossSchoolScope ? nil : schoolId)
            async let loadedSchools: [School] = policy.hasCrossSchoolScope ? client.fetchSchools() : []
            invoices = try await loadedInvoices
            schools = try await loadedSchools
            if policy.canManageRecipientInstructions, let schoolId {
                profile = try await client.fetchProfile(schoolId)
                async let loadedParents = client.fetchParents(schoolId)
                async let loadedChildren = AppConfiguration.workspaceBetaEnabled ? [] : client.fetchChildren(schoolId)
                parents = try await loadedParents
                children = try await loadedChildren
            } else {
                profile = nil
                parents = []
                children = []
            }
            phase = invoices.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            phase = .idle
        } catch {
            errorMessage = AppErrorMessage.school("Could not load payments", error)
            phase = .failed(errorMessage ?? "Could not load payments")
        }
    }

    func loadDetail(invoiceId: UUID, schoolId: UUID) async -> ZelleInvoice? {
        phase = .loading
        errorMessage = nil
        items = []
        submissions = []
        do {
            async let loadedInvoice = client.fetchInvoice(invoiceId)
            async let loadedItems = client.fetchItems(invoiceId)
            async let loadedSubmissions = client.fetchSubmissions(invoiceId)
            async let loadedProfile = client.fetchProfile(schoolId)
            let invoice = try await loadedInvoice
            items = try await loadedItems
            submissions = try await loadedSubmissions
            profile = try await loadedProfile
            phase = invoice == nil ? .empty : .loaded
            return invoice
        } catch where AppErrorMessage.isCancellation(error) {
            phase = .idle
            return nil
        } catch {
            errorMessage = AppErrorMessage.school("Could not load payment details", error)
            phase = .failed(errorMessage ?? "Could not load payment details")
            return nil
        }
    }

    func saveProfile(_ draft: ZelleProfileDraft, policy: PaymentAccessPolicy) async -> Bool {
        guard policy.canManageRecipientInstructions else { return false }
        return await mutate {
            self.profile = try await client.saveProfile(draft)
        }
    }

    func createInvoice(_ draft: ZelleInvoiceDraft, policy: PaymentAccessPolicy) async -> Bool {
        guard policy.canManage else { return false }
        return await mutate {
            let invoice = try await client.createInvoice(draft)
            self.invoices.insert(invoice, at: 0)
        }
    }

    func submit(_ draft: ZellePaymentSubmissionDraft, invoice: ZelleInvoice, policy: PaymentAccessPolicy) async -> ZellePaymentSubmission? {
        guard policy.canPay(invoice: invoice), draft.invoiceId == invoice.id, !isMutating else { return nil }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            let submission = try await client.submitPayment(draft)
            submissions.insert(submission, at: 0)
            return submission
        } catch {
            errorMessage = AppErrorMessage.school("Could not submit payment", error)
            return nil
        }
    }

    func review(_ submission: ZellePaymentSubmission, decision: String, note: String?, invoice: ZelleInvoice, policy: PaymentAccessPolicy) async -> ZelleInvoice? {
        guard policy.canReview(invoice: invoice), !isMutating else { return nil }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            let updated = try await client.reviewPayment(submission.id, decision, note)
            if let index = invoices.firstIndex(where: { $0.id == updated.id }) { invoices[index] = updated }
            return updated
        } catch {
            errorMessage = AppErrorMessage.school("Could not review payment", error)
            return nil
        }
    }

    func void(_ invoice: ZelleInvoice, reason: String, policy: PaymentAccessPolicy) async -> ZelleInvoice? {
        guard policy.canReview(invoice: invoice), !isMutating else { return nil }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            let updated = try await client.voidInvoice(invoice.id, reason)
            if let index = invoices.firstIndex(where: { $0.id == updated.id }) { invoices[index] = updated }
            return updated
        } catch {
            errorMessage = AppErrorMessage.school("Could not void invoice", error)
            return nil
        }
    }

    func resolve(_ invoice: ZelleInvoice, action: String, reason: String, policy: PaymentAccessPolicy) async -> ZelleInvoice? {
        guard policy.canReview(invoice: invoice), !isMutating else { return nil }
        var result: ZelleInvoice?
        _ = await mutate { result = try await client.resolveInvoice(invoice.id, action, reason) }
        return result
    }

    private func mutate(_ operation: () async throws -> Void) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Payment request failed", error)
            return false
        }
    }
}
