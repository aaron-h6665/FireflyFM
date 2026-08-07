import SwiftUI

struct PaymentInvoiceDetailView: View {
    let invoice: BillingInvoice
    let model: PaymentsModel
    let policy: PaymentAccessPolicy

    @State private var items: [BillingInvoiceItem] = []
    @State private var isLoadingItems = false
    @State private var browserItem: BillingBrowserItem?
    @State private var confirmsVoid = false

    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                    FireflySectionCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(invoice.description)
                                    .font(.title2.bold())
                                if let number = invoice.invoiceNumber {
                                    Text(number)
                                        .font(.subheadline)
                                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                                }
                            }
                            Spacer()
                            BillingStatusBadge(invoice: invoice)
                        }
                        Divider().padding(.vertical, 6)
                        detailRow("Total", BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))
                        detailRow("Paid", BillingMoney.string(cents: invoice.amountPaidCents, currency: invoice.currency))
                        detailRow("Remaining", BillingMoney.string(cents: invoice.amountRemainingCents, currency: invoice.currency))
                        if let dueAt = invoice.dueAt {
                            detailRow("Due", dueAt.formatted(date: .long, time: .omitted))
                        }
                    }

                    Text("Line items")
                        .font(.headline)
                    FireflySectionCard {
                        if isLoadingItems {
                            ProgressView()
                        } else if items.isEmpty {
                            Text("Line-item details are synchronizing from Stripe.")
                                .font(.subheadline)
                                .foregroundStyle(FireflyTheme.Colors.secondaryText)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
                                    Text(BillingMoney.string(cents: item.amountCents))
                                        .fontWeight(.semibold)
                                }
                                if index < items.count - 1 { Divider() }
                            }
                        }
                    }

                    if policy.canPay(invoice: invoice) {
                        parentActions
                    }
                    if policy.canManage {
                        directorActions
                    }

                    if let errorMessage = model.errorMessage {
                        FireflyInlineError(message: errorMessage)
                    }

                    Text("Payment credentials are entered only on Stripe's hosted page. FireflyFM stores invoice and status information, not card or bank credentials.")
                        .font(.caption)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                }
                .padding()
            }
        }
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $browserItem) { item in
            FireflySafariView(url: item.url).ignoresSafeArea()
        }
        .confirmationDialog("Void this invoice?", isPresented: $confirmsVoid, titleVisibility: .visible) {
            Button("Void Invoice", role: .destructive) {
                Task { _ = await model.perform("void", invoice: invoice, policy: policy) }
            }
        } message: {
            Text("The parent will no longer be able to pay it. This cannot be reversed in FireflyFM.")
        }
        .task { await loadItems() }
    }

    private var parentActions: some View {
        VStack(spacing: 10) {
            if invoice.status == .open {
                Button {
                    openDocument("pay")
                } label: {
                    Label("Pay securely with Stripe", systemImage: "lock.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isMutating)
            }
            Button {
                openDocument("invoicePDF")
            } label: {
                Label("View invoice PDF", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isMutating)
            if invoice.status == .paid {
                Button {
                    openDocument("receipt")
                } label: {
                    Label("View receipt", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isMutating)
            }
        }
    }

    private var directorActions: some View {
        VStack(spacing: 10) {
            if invoice.status == .open {
                Button {
                    Task { _ = await model.perform("resend", invoice: invoice, policy: policy) }
                } label: {
                    Label("Resend invoice email", systemImage: "envelope.arrow.triangle.branch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isMutating)

                Button(role: .destructive) { confirmsVoid = true } label: {
                    Label("Void invoice", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isMutating)
            }
            Text("Refunds and disputes are handled in the connected school's Stripe Dashboard during beta.")
                .font(.caption)
                .foregroundStyle(FireflyTheme.Colors.secondaryText)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(FireflyTheme.Colors.secondaryText)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func openDocument(_ kind: String) {
        Task {
            if let url = await model.documentURL(invoice: invoice, kind: kind, policy: policy) {
                browserItem = BillingBrowserItem(url: url)
            }
        }
    }

    @MainActor
    private func loadItems() async {
        isLoadingItems = true
        defer { isLoadingItems = false }
        items = (try? await model.items(for: invoice.id)) ?? []
    }
}
