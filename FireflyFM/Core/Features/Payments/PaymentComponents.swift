import SwiftUI

struct BillingStatusBadge: View {
    let invoice: ZelleInvoice

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
        invoice.isPastDue || [.rejected, .expired, .void].contains(invoice.status) ? .red : FireflyTheme.Colors.primaryText
    }

    private var background: Color {
        switch invoice.status {
        case .paid: .green.opacity(0.2)
        case .paymentSubmitted, .underReview: .orange.opacity(0.22)
        case .rejected, .expired, .void: .red.opacity(0.16)
        case .open: FireflyTheme.Colors.wingBlue.opacity(0.35)
        case .draft: .yellow.opacity(0.22)
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
    let invoice: ZelleInvoice
    var schoolName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text((invoice.isDemo == true ? "DEMO · " : "") + invoice.description)
                        .font(.headline)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    Text(invoice.invoiceNumber)
                        .font(.caption)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
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
