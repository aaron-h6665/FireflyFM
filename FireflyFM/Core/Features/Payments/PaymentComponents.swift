import SwiftUI

struct BillingStatusBadge: View {
    let invoice: BillingInvoice

    var body: some View {
        Text(invoice.displayStatus)
            .font(.caption.bold())
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .accessibilityLabel("Status: \(invoice.displayStatus)")
    }

    private var foreground: Color {
        [.failed, .disputed].contains(invoice.paymentStatus) || invoice.isPastDue ? .red : FireflyTheme.Colors.primaryText
    }

    private var background: Color {
        if invoice.paymentStatus == .processing { return .orange.opacity(0.22) }
        if invoice.paymentStatus == .refunded { return .purple.opacity(0.18) }
        if invoice.paymentStatus == .disputed || invoice.isPastDue { return .red.opacity(0.16) }
        switch invoice.status {
        case .paid: return .green.opacity(0.2)
        case .open: return FireflyTheme.Colors.wingBlue.opacity(0.35)
        case .void, .uncollectible: return .gray.opacity(0.2)
        case .draft: return .yellow.opacity(0.22)
        }
    }
}

struct BillingSummaryCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        FireflySectionCard {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(FireflyTheme.Colors.secondaryText)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(FireflyTheme.Colors.primaryText)
                .padding(.top, 4)
        }
    }
}

struct BillingInvoiceRow: View {
    let invoice: BillingInvoice
    var schoolName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(invoice.description)
                        .font(.headline)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    if let invoiceNumber = invoice.invoiceNumber {
                        Text(invoiceNumber)
                            .font(.caption)
                            .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    }
                }
                Spacer()
                BillingStatusBadge(invoice: invoice)
            }
            if let schoolName {
                Label(schoolName, systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(FireflyTheme.Colors.secondaryText)
            }
            HStack {
                Text(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))
                    .font(.title3.bold())
                Spacer()
                if let dueAt = invoice.dueAt {
                    Text("Due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(invoice.isPastDue ? .red : FireflyTheme.Colors.secondaryText)
                }
            }
            .foregroundStyle(FireflyTheme.Colors.primaryText)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

struct BillingBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}
