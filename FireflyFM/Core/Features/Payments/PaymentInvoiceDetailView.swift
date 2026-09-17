import SwiftUI
import Supabase

struct PaymentInvoiceDetailView: View {
    let model: PaymentsModel
    let policy: PaymentAccessPolicy
    let onChanged: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var payerName: String?
    @State private var resolutionAction: String?
    @State private var resolutionReason = ""
    @State private var invoice: ZelleInvoice
    @State private var detailAvailable = true
    @State private var showsSubmission = false
    @State private var reviewTarget: ZellePaymentSubmission?
    @State private var showsVoidSheet = false
    @State private var showingReceiptDocument = false
    @State private var showingInvoiceDocument = false

    init(invoice: ZelleInvoice, model: PaymentsModel, policy: PaymentAccessPolicy, onChanged: @escaping () -> Void = {}) {
        self.model = model
        self.policy = policy
        self.onChanged = onChanged
        _invoice = State(initialValue: invoice)
    }

    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                    if detailAvailable {
                    invoiceCard
                    lineItems
                    if policy.canPay(invoice: invoice) { submissionHistory }
                    #if DEBUG && targetEnvironment(simulator)
                    if AppConfiguration.paymentDemoEnabled && invoice.isDemo == true {
                        ZelleDemoLedgerView(invoice: invoice, policy: policy)
                    }
                    #endif
                    if policy.canPay(invoice: invoice) { payerActions }
                    if policy.canReview(invoice: invoice) { reviewerActions }
                    if invoice.status == .paid { receiptCard }
                    if let errorMessage = model.errorMessage { FireflyInlineError(message: errorMessage) }
                    safetyNote
                    } else {
                        FireflyInlineError(message: "This invoice is no longer available for this account.")
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingInvoiceDocument = true
                    } label: {
                        Label("View / Print Invoice", systemImage: "doc.text")
                    }

                    if invoice.status == .paid {
                        Button {
                            showingReceiptDocument = true
                        } label: {
                            Label("View / Print Receipt", systemImage: "checkmark.seal")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingReceiptDocument) {
            PaymentReceiptView(
                invoice: invoice,
                items: model.items,
                schoolName: invoiceSchoolName,
                reviewerName: reviewerReceiptName
            )
        }
        .sheet(isPresented: $showingInvoiceDocument) {
            PaymentInvoiceDocumentView(
                invoice: invoice,
                items: model.items,
                schoolName: invoiceSchoolName,
                profile: model.profile
            )
        }
        .sheet(isPresented: $showsSubmission) {
            ZellePaymentSubmissionView(invoice: invoice, profile: model.profile, model: model, policy: policy) { submission in
                Task {
                    await reloadDetail()
                    onChanged()
                }
            }
        }
        .sheet(item: $reviewTarget) { submission in
            ZellePaymentReviewView(submission: submission, invoice: invoice, model: model, policy: policy) { updated in
                invoice = updated
                Task {
                    await reloadDetail()
                    onChanged()
                }
            }
        }
        .sheet(isPresented: $showsVoidSheet) {
            ZelleVoidInvoiceView(invoice: invoice, model: model, policy: policy) { updated in
                invoice = updated
                Task { await refreshAccessAndDetail() }
                onChanged()
            }
        }
        .task {
            await reloadDetail()
            if AppConfiguration.workspaceBetaEnabled {
                struct Params: Encodable { let input_school_id: UUID }
                do {
                    let labels: [WorkspacePersonLabel] = try await AppConstants.supabase.rpc("fetch_workspace_payer_labels", params: Params(input_school_id: invoice.schoolId)).execute().value
                    payerName = labels.first { $0.user_id == invoice.payerUserId }?.display_name
                } catch { payerName = nil }
            }
        }
        .refreshable { await refreshAccessAndDetail() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshAccessAndDetail() } }
        }
        .sheet(isPresented: Binding(get: { resolutionAction != nil }, set: { if !$0 { resolutionAction = nil } })) {
            NavigationStack {
                Form {
                    Text(resolutionAction == "waive" ? "Waive this requirement without recording a payment. This may release onboarding access." : "Create a replacement with the same amount and current recipient instructions. The canceled invoice remains in history.")
                    TextField("Required reason", text: $resolutionReason, axis: .vertical)
                    if let error = model.errorMessage { FireflyInlineError(message: error) }
                }
                .navigationTitle(resolutionAction == "waive" ? "Waive Requirement" : "Replace Invoice")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { resolutionAction = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Confirm") {
                            guard let action = resolutionAction else { return }
                            Task {
                                if let updated = await model.resolve(invoice, action: action, reason: resolutionReason.trimmed, policy: policy) {
                                    invoice = updated
                                    resolutionAction = nil
                                    await refreshAccessAndDetail()
                                    onChanged()
                                }
                            }
                        }.disabled(resolutionReason.trimmed.isEmpty || model.isMutating)
                    }
                }
            }
        }
    }

    private var invoiceCard: some View {
        WorkspaceDetailCard {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(invoice.description).font(.title2.bold())
                    Text(invoice.invoiceNumber)
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                }
                Spacer()
                BillingStatusBadge(invoice: invoice)
            }
            if invoice.isDemo == true { Label("DEMO — no money moved", systemImage: "testtube.2").foregroundStyle(.orange) }
            Divider().padding(.vertical, 6)
            if AppConfiguration.workspaceBetaEnabled {
                detailRow("Billed to", payerName ?? "Payer name unavailable")
                detailRow("Role", invoice.payerRole.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                detailRow("Payable to", invoice.recipientSnapshot?.displayName ?? "Recipient unavailable")
            }
            detailRow("Total", BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))
            detailRow("Verified paid", BillingMoney.string(cents: invoice.amountPaidCents, currency: invoice.currency))
            detailRow("Remaining", BillingMoney.string(cents: invoice.amountRemainingCents, currency: invoice.currency))
            if let dueAt = invoice.dueAt { detailRow("Due", dueAt.formatted(date: .long, time: .omitted)) }
            if invoice.isOnboardingInvoice {
                Label("Required onboarding payment", systemImage: "checklist")
                    .font(.caption.bold())
                    .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    .padding(.top, 4)
            }
            }
        }
    }

    private var lineItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line items").font(.headline)
            WorkspaceDetailCard {
                if model.phase.isLoading && model.items.isEmpty {
                    ProgressView()
                } else if model.items.isEmpty {
                    Text("No line-item details are available.")
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                } else {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.description)
                                if item.quantity > 1 {
                                    Text("\(item.quantity) × \(BillingMoney.string(cents: item.unitAmountCents))")
                                        .font(.caption)
                                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                                }
                            }
                            Spacer()
                            Text(BillingMoney.string(cents: item.amountCents)).fontWeight(.semibold)
                        }
                        if index < model.items.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var payerActions: some View {
        if [.open, .rejected].contains(invoice.status) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pay with Zelle").font(.headline)
                if let recipient = invoice.recipientSnapshot {
                    WorkspaceDetailCard {
                        Text(invoice.isDemo == true ? "Use the demo transfer controls below. Do not send real money." : "Send exactly \(BillingMoney.string(cents: invoice.amountDueCents)) using your own bank’s Zelle experience.")
                            .font(.subheadline)
                        Divider().padding(.vertical, 4)
                        detailRow("Recipient", recipient.displayName)
                        detailRow(recipient.type.title, recipient.value)
                        detailRow("Memo", recipient.memo)
                        if let instructions = recipient.instructions, !instructions.isEmpty {
                            Text(instructions)
                                .font(.caption)
                                .foregroundStyle(FireflyTheme.Colors.secondaryText)
                                .padding(.top, 4)
                        }
                        Button("Copy payment instructions") {
                            UIPasteboard.general.string = "\(recipient.displayName)\n\(recipient.value)\n\(BillingMoney.string(cents: invoice.amountDueCents))\nMemo: \(recipient.memo)"
                        }
                        if invoice.status == .rejected {
                            Text("Review \(reviewerFeedbackOwner) feedback below. Correcting a reference does not require another payment.").font(.caption)
                        }
                    }
                    Button {
                        showsSubmission = true
                    } label: {
                        Label(invoice.status == .rejected ? "Submit updated confirmation" : "I sent this payment", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isMutating)
                } else {
                    FireflyInlineError(message: "The payment instructions are currently unavailable. Contact \(reviewerContact) before sending a payment.")
                }
            }
        } else if [.paymentSubmitted, .underReview].contains(invoice.status) {
            WorkspaceDetailCard {
                Label("Your confirmation has been submitted. \(reviewerSubject) must verify the transfer before it is marked paid.", systemImage: "clock.badge.checkmark")
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var reviewerActions: some View {
        if !model.submissions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Payment review").font(.headline)
                ForEach(model.submissions) { submission in
                    WorkspaceDetailCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(BillingMoney.string(cents: submission.amountCents))
                                    .font(.headline)
                                Spacer()
                                Text(submission.status.title).font(.caption.bold())
                            }
                            Text("Sent \(submission.sentAt.formatted(date: .abbreviated, time: .shortened)) · Reference \(submission.confirmationReference)")
                                .font(.caption)
                                .foregroundStyle(FireflyTheme.Colors.secondaryText)
                            if let note = submission.reviewerNote, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(FireflyTheme.Colors.secondaryText)
                            }
                            if [.submitted, .underReview].contains(submission.status) {
                                Button("Verify in bank & review") { reviewTarget = submission }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.isMutating)
                            }
                        }
                    }
                }
            }
        }
        if ![.paid, .void].contains(invoice.status) {
            Button(role: .destructive) { showsVoidSheet = true } label: {
                Label("Void invoice", systemImage: "xmark.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isMutating)
        }
        if invoice.status == .void {
            Button("Create replacement invoice") { resolutionReason = ""; resolutionAction = "replace" }
        }
        if invoice.onboardingRequirementInstanceId != nil && invoice.status != .paid {
            Button("Waive payment requirement") { resolutionReason = ""; resolutionAction = "waive" }
        }
    }

    private var submissionHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.submissions) { submission in
                WorkspaceDetailCard {
                    Text(submission.status.title).font(.headline)
                    Text("Reference: \(submission.confirmationReference)").font(.caption)
                    if let note = submission.reviewerNote { Text(note) }
                    if submission.status == .rejected {
                        Text("Update the confirmation or contact \(reviewerContact). Do not send money again just to correct this submission.").font(.caption)
                    }
                }
            }
        }
    }

    private var receiptCard: some View {
        WorkspaceDetailCard {
            Label(invoice.isDemo == true ? "DEMO receipt — no money moved" : "Receipt", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Verified by \(reviewerReceiptName) on \(invoice.paidAt?.formatted(date: .long, time: .shortened) ?? "the recorded payment date"). Keep this receipt number for your records: \(invoice.invoiceNumber).")
                .font(.subheadline)
                .foregroundStyle(FireflyTheme.Colors.secondaryText)
            Button {
                showingReceiptDocument = true
            } label: {
                Label("View / Print Official Receipt", systemImage: "printer")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    private var safetyNote: some View {
        Text("Security: FireflyFM never collects a bank password, account number, Zelle login, or payment screenshot. A confirmation reference is a review aid, not proof of payment.")
            .font(.caption)
            .foregroundStyle(FireflyTheme.Colors.secondaryText)
    }

    private var isHQReviewedOnboardingPayment: Bool {
        invoice.isOnboardingInvoice && invoice.payerRole == .schoolDirector
    }

    private var reviewerSubject: String {
        isHQReviewedOnboardingPayment ? "FireflyFM HQ" : "Your school director"
    }

    private var reviewerFeedbackOwner: String {
        isHQReviewedOnboardingPayment ? "FireflyFM HQ’s" : "your school director’s"
    }

    private var reviewerContact: String {
        isHQReviewedOnboardingPayment ? "FireflyFM HQ" : "your school director"
    }

    private var invoiceSchoolName: String {
        if let recipient = invoice.recipientSnapshot?.displayName { return recipient }
        return model.schools.first(where: { $0.id == invoice.schoolId })?.name ?? appSession.activeSchool?.name ?? "School"
    }

    private var reviewerReceiptName: String {
        if isHQReviewedOnboardingPayment {
            return "FireflyFM HQ"
        }
        return "\(invoiceSchoolName) Administration"
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(FireflyTheme.Colors.secondaryText)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    @MainActor
    private func refreshAccessAndDetail() async {
        await reloadDetail()
        await appSession.refresh(selecting: appSession.activeMembershipId)
    }

    @MainActor
    private func reloadDetail() async {
        if let refreshed = await model.loadDetail(invoiceId: invoice.id, schoolId: invoice.schoolId) {
            invoice = refreshed
            detailAvailable = true
        } else {
            detailAvailable = false
        }
    }
}

struct ZellePaymentSubmissionView: View {
    let invoice: ZelleInvoice
    let profile: SchoolZelleProfile?
    let model: PaymentsModel
    let policy: PaymentAccessPolicy
    let onSubmitted: (ZellePaymentSubmission) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sentAt = Date()
    @State private var reference = ""
    @State private var validationMessage: String?
    @State private var idempotencyKey = "ios:zelle-submission:\(UUID().uuidString)"

    var body: some View {
        NavigationStack {
            Form {
                Section("Confirm your transfer") {
                    LabeledContent("Amount", value: BillingMoney.string(cents: invoice.amountDueCents))
                    DatePicker("When did you send it?", selection: $sentAt, in: Date().addingTimeInterval(-180 * 86400)...Date().addingTimeInterval(15 * 60), displayedComponents: [.date, .hourAndMinute])
                    TextField("Confirmation reference", text: $reference)
                        .textInputAutocapitalization(.characters)
                    Text("Enter only the short confirmation reference from your bank. Do not upload a screenshot or enter account, routing, or login information.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if invoice.isDemo == true {
                    Section("Demo only") { Text("Paste a TEST reference generated in the simulated bank ledger. No real money moves.") }
                }
                if let validationMessage { FireflyInlineError(message: validationMessage) }
                if let errorMessage = model.errorMessage { FireflyInlineError(message: errorMessage) }
            }
            .navigationTitle("Submit Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isMutating ? "Submitting" : "Submit") { submit() }.disabled(model.isMutating)
                }
            }
        }
    }

    private func submit() {
        let normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.range(of: "^[A-Z0-9-]{4,64}$", options: .regularExpression) != nil else {
            validationMessage = "Use the short confirmation reference only (letters, numbers, and hyphens)."
            return
        }
        validationMessage = nil
        let draft = ZellePaymentSubmissionDraft(
            invoiceId: invoice.id,
            amountCents: invoice.amountDueCents,
            sentAt: sentAt,
            confirmationReference: normalized,
            idempotencyKey: idempotencyKey
        )
        Task {
            if let submission = await model.submit(draft, invoice: invoice, policy: policy) {
                onSubmitted(submission)
                dismiss()
            }
        }
    }
}

struct ZellePaymentReviewView: View {
    let submission: ZellePaymentSubmission
    let invoice: ZelleInvoice
    let model: PaymentsModel
    let policy: PaymentAccessPolicy
    let onReviewed: (ZelleInvoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Before approving") {
                    Text(invoice.isDemo == true ? "Compare the reference with the received demo bank transfer before approving. No real money moves." : "Verify the transfer in the school’s bank experience. The payer’s reference is not proof on its own.")
                        .font(.subheadline)
                    LabeledContent("Invoice", value: invoice.invoiceNumber)
                    LabeledContent("Amount", value: BillingMoney.string(cents: submission.amountCents))
                    LabeledContent("Reference", value: submission.confirmationReference)
                }
                Section("Feedback if an update is needed") {
                    TextField("Optional for approval; required for rejection", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if let validationMessage { FireflyInlineError(message: validationMessage) }
                if let errorMessage = model.errorMessage { FireflyInlineError(message: errorMessage) }
            }
            .navigationTitle("Review Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Decide") {
                        Button("Approve verified payment") { review("approved") }
                        Button("Request an update", role: .destructive) { review("rejected") }
                    }
                    .disabled(model.isMutating)
                }
            }
        }
    }

    private func review(_ decision: String) {
        if decision == "rejected" && note.trimmed.isEmpty {
            validationMessage = "Explain what the payer needs to correct."
            return
        }
        validationMessage = nil
        Task {
            if let updated = await model.review(submission, decision: decision, note: note.nilIfBlank, invoice: invoice, policy: policy) {
                onReviewed(updated)
                dismiss()
            }
        }
    }
}

struct ZelleVoidInvoiceView: View {
    let invoice: ZelleInvoice
    let model: PaymentsModel
    let policy: PaymentAccessPolicy
    let onVoided: (ZelleInvoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Void invoice") {
                    Text("Voiding cancels this invoice and preserves its history. It does not waive an onboarding requirement or refund a transfer. Use a separate waiver or replacement if needed.")
                    TextField("Reason", text: $reason, axis: .vertical).lineLimit(2...5)
                }
                if let errorMessage = model.errorMessage { FireflyInlineError(message: errorMessage) }
            }
            .navigationTitle("Void Invoice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Void", role: .destructive) { voidInvoice() }
                        .disabled(reason.trimmed.isEmpty || model.isMutating)
                }
            }
        }
    }

    private func voidInvoice() {
        Task {
            if let updated = await model.void(invoice, reason: reason.trimmed, policy: policy) {
                onVoided(updated)
                dismiss()
            }
        }
    }
}

struct ZelleInvoiceDestinationView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    let invoiceId: UUID
    let schoolId: UUID

    @State private var model = PaymentsModel()
    @State private var invoice: ZelleInvoice?

    private var policy: PaymentAccessPolicy { PaymentAccessPolicy(context: appSession.accessContext()) }

    var body: some View {
        Group {
            if let invoice {
                PaymentInvoiceDetailView(invoice: invoice, model: model, policy: policy)
            } else if model.phase.isLoading {
                ProgressView("Loading payment…")
            } else {
                FireflyEmptyState(
                    title: "Payment unavailable",
                    message: model.errorMessage ?? "This payment step is no longer available.",
                    systemImage: "lock.fill"
                )
                .padding()
            }
        }
        .task { invoice = await model.loadDetail(invoiceId: invoiceId, schoolId: schoolId) }
    }
}
