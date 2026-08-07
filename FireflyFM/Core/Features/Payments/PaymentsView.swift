import SwiftUI

struct PaymentsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var model = PaymentsModel()
    @State private var showsComposer = false
    @State private var browserItem: BillingBrowserItem?

    private var policy: PaymentAccessPolicy {
        PaymentAccessPolicy(context: appSession.accessContext())
    }

    private var schoolId: UUID? { appSession.activeSchool?.id }

    var body: some View {
        FireflyScreen {
            Group {
                if !policy.canView {
                    FireflyEmptyState(
                        title: "Payments unavailable",
                        message: "Your school role does not include billing access.",
                        systemImage: "lock.fill"
                    )
                    .padding()
                } else if model.phase.isLoading && model.invoices.isEmpty {
                    ProgressView("Loading payments…")
                } else {
                    content
                }
            }
        }
        .navigationTitle("Payments")
        .toolbar {
            if policy.canManage {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsComposer = true
                    } label: {
                        Label("New Invoice", systemImage: "plus")
                    }
                    .disabled(model.account?.isReady != true || model.isMutating)
                }
            }
        }
        .sheet(isPresented: $showsComposer) {
            if let schoolId {
                PaymentInvoiceComposerView(
                    schoolId: schoolId,
                    parents: model.parents,
                    children: model.children,
                    model: model,
                    policy: policy
                ) {
                    Task { await reload() }
                }
            }
        }
        .sheet(item: $browserItem, onDismiss: { Task { await reload() } }) { item in
            FireflySafariView(url: item.url).ignoresSafeArea()
        }
        .task(id: "\(appSession.activeMembershipId?.uuidString ?? "none")-\(appSession.role?.rawValue ?? "none")") {
            await reload()
        }
        .refreshable { await reload() }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(FireflyTheme.Colors.secondaryText)

                if policy.canManage, let schoolId {
                    paymentSetupCard(schoolId: schoolId)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    BillingSummaryCard(
                        title: policy.context.role == .parent ? "Amount due" : "Outstanding",
                        value: BillingMoney.string(cents: model.outstandingCents),
                        systemImage: "clock.badge.exclamationmark"
                    )
                    BillingSummaryCard(
                        title: "Collected",
                        value: BillingMoney.string(cents: model.collectedCents),
                        systemImage: "checkmark.circle.fill"
                    )
                }

                if model.overdueCount > 0 {
                    Label("\(model.overdueCount) overdue invoice\(model.overdueCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.bold())
                }

                if let errorMessage = model.errorMessage {
                    FireflyInlineError(message: errorMessage)
                }

                Text("Invoices")
                    .font(.title3.bold())
                    .foregroundStyle(FireflyTheme.Colors.primaryText)

                if model.invoices.isEmpty {
                    FireflyEmptyState(
                        title: "No invoices yet",
                        message: policy.canManage ? "Complete setup, then issue the first invoice." : "New invoices will appear here.",
                        systemImage: "doc.text"
                    )
                } else {
                    FireflySectionCard {
                        ForEach(Array(model.invoices.enumerated()), id: \.element.id) { index, invoice in
                            NavigationLink {
                                PaymentInvoiceDetailView(invoice: invoice, model: model, policy: policy)
                            } label: {
                                BillingInvoiceRow(invoice: invoice, schoolName: schoolName(for: invoice.schoolId))
                            }
                            .buttonStyle(.plain)
                            if index < model.invoices.count - 1 { Divider() }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var description: String {
        switch policy.context.role {
        case .parent: "Pay school invoices securely through Stripe and download invoices or receipts. FireflyFM never stores your card or bank credentials."
        case .schoolDirector: "Issue invoices and reconcile Stripe payment status for this school. Refunds and disputes remain in the Stripe Dashboard during beta."
        case .hqDirector: "Read-only cross-school payment oversight. Financial actions remain with each school director."
        default: "School billing."
        }
    }

    private func paymentSetupCard(schoolId: UUID) -> some View {
        FireflySectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.account?.isReady == true ? "checkmark.shield.fill" : "creditcard.trianglebadge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(model.account?.isReady == true ? .green : .orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.account?.sandbox == false ? "Stripe live account" : "Stripe beta account")
                        .font(.headline)
                    Text(setupDescription)
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    if model.account?.isReady != true {
                        Button("Continue Stripe setup") {
                            Task {
                                if let url = await model.onboardingURL(schoolId: schoolId, policy: policy) {
                                    browserItem = BillingBrowserItem(url: url)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isMutating)
                    }
                }
            }
        }
    }

    private var setupDescription: String {
        guard let account = model.account else {
            return "Connect this school to Stripe before issuing beta invoices."
        }
        if account.isReady { return "Charges and payouts are enabled.\(account.sandbox ? " This account uses Stripe test mode." : "")" }
        if account.requirementsDueCount > 0 { return "Stripe needs \(account.requirementsDueCount) more verification item(s)." }
        return "Stripe onboarding is not complete yet."
    }

    private func schoolName(for id: UUID) -> String? {
        guard policy.hasCrossSchoolScope else { return nil }
        return model.schools.first(where: { $0.id == id })?.name ?? "School"
    }

    @MainActor
    private func reload() async {
        await model.load(schoolId: schoolId, policy: policy)
    }
}
