import SwiftUI

struct BillingStatusBadge: View {
    let invoice: ZelleInvoice

    var body: some View {
        Text(invoice.displayStatus)
            .font(FireflyTheme.Typography.badge)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .accessibilityLabel("Status: \(invoice.displayStatus)")
    }

    private var foreground: Color {
        invoice.isPastDue || [.rejected, .expired, .void].contains(invoice.status)
            ? FireflyTheme.Colors.danger
            : FireflyTheme.Colors.primaryText
    }

    private var background: Color {
        switch invoice.status {
        case .paid: FireflyTheme.Colors.successBackground
        case .paymentSubmitted, .underReview: FireflyTheme.Colors.attentionBackground
        case .rejected, .expired, .void: FireflyTheme.Colors.dangerBackground
        case .open: FireflyTheme.Colors.informationBackground
        case .draft: FireflyTheme.Colors.attentionBackground
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
                .font(FireflyTheme.Typography.badge)
                .foregroundStyle(FireflyTheme.Colors.secondaryText)
            Text(value)
                .font(FireflyTheme.Typography.monetaryValue)
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
                        .font(FireflyTheme.Typography.rowTitle)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    Text(invoice.invoiceNumber)
                        .font(FireflyTheme.Typography.supporting)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                }
                Spacer()
                BillingStatusBadge(invoice: invoice)
            }
            if let schoolName {
                Label(schoolName, systemImage: "building.2")
                    .font(FireflyTheme.Typography.supporting)
                    .foregroundStyle(FireflyTheme.Colors.secondaryText)
            }
            HStack {
                Text(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))
                    .font(FireflyTheme.Typography.monetaryValue)
                Spacer()
                if let dueAt = invoice.dueAt {
                    Text("Due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(FireflyTheme.Typography.supporting)
                        .foregroundStyle(invoice.isPastDue ? FireflyTheme.Colors.danger : FireflyTheme.Colors.secondaryText)
                }
            }
            .foregroundStyle(FireflyTheme.Colors.primaryText)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
