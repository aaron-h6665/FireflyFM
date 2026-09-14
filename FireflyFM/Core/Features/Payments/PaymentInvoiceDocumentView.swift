import SwiftUI
import UIKit

struct PaymentInvoiceDocumentView: View {
    let invoice: ZelleInvoice
    let items: [ZelleInvoiceItem]
    let schoolName: String
    let profile: SchoolZelleProfile?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    invoiceDocument
                }
                .padding()
            }
            .background(FireflyTheme.Colors.background)
            .navigationTitle("Invoice Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        ShareLink(
                            item: invoiceText,
                            subject: Text("Invoice \(invoice.invoiceNumber) - \(schoolName)"),
                            message: Text("Invoice for \(invoice.description)")
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            printInvoice()
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                    }
                }
            }
        }
    }

    private var invoiceDocument: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schoolName)
                        .font(.title2.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    Text("INVOICE")
                        .font(.caption.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryAction)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    BillingStatusBadge(invoice: invoice)

                    if invoice.isDemo == true {
                        Text("DEMO - NO MONEY MOVED")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider()

            // Key details
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Invoice Number:")
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    Text(invoice.invoiceNumber)
                        .font(.subheadline.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                }
                if let dueAt = invoice.dueAt {
                    GridRow {
                        Text("Due Date:")
                            .font(.subheadline)
                            .foregroundStyle(FireflyTheme.Colors.secondaryText)
                        Text(dueAt.formatted(date: .long, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(invoice.isPastDue ? .red : FireflyTheme.Colors.primaryText)
                    }
                }
                if let issuedAt = invoice.issuedAt {
                    GridRow {
                        Text("Issue Date:")
                            .font(.subheadline)
                            .foregroundStyle(FireflyTheme.Colors.secondaryText)
                        Text(issuedAt.formatted(date: .long, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(FireflyTheme.Colors.primaryText)
                    }
                }
                GridRow {
                    Text("Description:")
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    Text(invoice.description)
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                }
            }

            Divider()

            // Line items table
            VStack(alignment: .leading, spacing: 10) {
                Text("Itemized Charges")
                    .font(.headline)
                    .foregroundStyle(FireflyTheme.Colors.primaryText)

                ForEach(items) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.description)
                                .font(.subheadline)
                                .foregroundStyle(FireflyTheme.Colors.primaryText)
                            if item.quantity > 1 {
                                Text("\(item.quantity) × \(BillingMoney.string(cents: item.unitAmountCents, currency: invoice.currency))")
                                    .font(.caption)
                                    .foregroundStyle(FireflyTheme.Colors.secondaryText)
                            }
                        }
                        Spacer()
                        Text(BillingMoney.string(cents: item.amountCents, currency: invoice.currency))
                            .font(.subheadline.bold())
                            .foregroundStyle(FireflyTheme.Colors.primaryText)
                    }
                    .padding(.vertical, 2)
                }

                if items.isEmpty {
                    HStack {
                        Text(invoice.description)
                            .font(.subheadline)
                        Spacer()
                        Text(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))
                            .font(.subheadline.bold())
                    }
                }
            }

            Divider()

            // Totals
            VStack(spacing: 8) {
                HStack {
                    Text("Total Amount Due")
                        .font(.headline)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    Spacer()
                    Text(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))
                        .font(.title3.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryAction)
                }

                if invoice.amountPaidCents > 0 {
                    HStack {
                        Text("Paid to Date")
                            .foregroundStyle(.green)
                        Spacer()
                        Text(BillingMoney.string(cents: invoice.amountPaidCents, currency: invoice.currency))
                            .foregroundStyle(.green)
                    }
                    .font(.subheadline)

                    HStack {
                        Text("Balance Remaining")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(BillingMoney.string(cents: invoice.amountRemainingCents, currency: invoice.currency))
                            .font(.subheadline.bold())
                    }
                }
            }

            // Payment instructions
            if let profile, profile.active {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label("How to Pay via Zelle", systemImage: "dollarsign.circle.fill")
                        .font(.headline)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)

                    Text("Send the exact amount from your bank's Zelle experience:")
                        .font(.caption)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recipient: \(profile.recipientDisplayName)")
                        Text("Send To: \(profile.recipientValue)")
                        Text("Memo: \(profile.memoPrefix) \(invoice.invoiceNumber)")
                    }
                    .font(.caption.monospaced())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(20)
        .background(FireflyTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FireflyTheme.Colors.separator, lineWidth: 1)
        )
    }

    private var invoiceText: String {
        var lines: [String] = []
        lines.append("========================================")
        lines.append(schoolName.uppercased())
        lines.append("INVOICE")
        lines.append("========================================")
        lines.append("Invoice Number: \(invoice.invoiceNumber)")
        if let dueAt = invoice.dueAt {
            lines.append("Due Date: \(dueAt.formatted(date: .long, time: .omitted))")
        }
        if let issuedAt = invoice.issuedAt {
            lines.append("Issue Date: \(issuedAt.formatted(date: .long, time: .omitted))")
        }
        lines.append("Description: \(invoice.description)")
        lines.append("Status: \(invoice.displayStatus)")
        lines.append("----------------------------------------")
        lines.append("ITEMS:")
        if items.isEmpty {
            lines.append("• \(invoice.description) — \(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))")
        } else {
            for item in items {
                lines.append("• \(item.description) (x\(item.quantity)) — \(BillingMoney.string(cents: item.amountCents, currency: invoice.currency))")
            }
        }
        lines.append("----------------------------------------")
        lines.append("TOTAL DUE: \(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))")
        if invoice.amountPaidCents > 0 {
            lines.append("AMOUNT PAID: \(BillingMoney.string(cents: invoice.amountPaidCents, currency: invoice.currency))")
            lines.append("REMAINING: \(BillingMoney.string(cents: invoice.amountRemainingCents, currency: invoice.currency))")
        }
        if let profile, profile.active {
            lines.append("----------------------------------------")
            lines.append("ZELLE PAYMENT INSTRUCTIONS:")
            lines.append("Recipient: \(profile.recipientDisplayName)")
            lines.append("Send to: \(profile.recipientValue)")
            lines.append("Memo: \(profile.memoPrefix) \(invoice.invoiceNumber)")
        }
        lines.append("========================================")
        return lines.joined(separator: "\n")
    }

    private func printInvoice() {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "Invoice-\(invoice.invoiceNumber)"
        printController.printInfo = printInfo

        var itemsHtml = ""
        if items.isEmpty {
            itemsHtml = "<tr><td>\(invoice.description)</td><td style='text-align:right'>1</td><td style='text-align:right'>\(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))</td></tr>"
        } else {
            for item in items {
                itemsHtml += "<tr><td>\(item.description)</td><td style='text-align:right'>\(item.quantity)</td><td style='text-align:right'>\(BillingMoney.string(cents: item.amountCents, currency: invoice.currency))</td></tr>"
            }
        }

        let html = """
        <html>
        <head>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; padding: 24px; color: #1a1a1a; }
                .header { border-bottom: 2px solid #333; padding-bottom: 12px; margin-bottom: 20px; }
                h1 { margin: 0 0 6px 0; font-size: 24px; }
                .badge { color: #2563eb; font-weight: bold; font-size: 14px; text-transform: uppercase; }
                table { width: 100%; border-collapse: collapse; margin-top: 16px; margin-bottom: 16px; }
                th, td { padding: 8px 4px; text-align: left; border-bottom: 1px solid #e5e7eb; font-size: 13px; }
                th { color: #6b7280; font-weight: 600; }
                .totals { margin-top: 16px; border-top: 2px solid #333; padding-top: 12px; }
                .footer { margin-top: 28px; font-size: 11px; color: #6b7280; border-top: 1px solid #e5e7eb; padding-top: 10px; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>\(schoolName)</h1>
                <div class="badge">Invoice &bull; \(invoice.displayStatus)</div>
            </div>
            <div>
                <p><strong>Invoice #:</strong> \(invoice.invoiceNumber)</p>
                <p><strong>Due Date:</strong> \(invoice.dueAt?.formatted(date: .long, time: .omitted) ?? "—")</p>
                <p><strong>Description:</strong> \(invoice.description)</p>
            </div>
            <table>
                <thead>
                    <tr><th>Item</th><th style="text-align:right">Qty</th><th style="text-align:right">Amount</th></tr>
                </thead>
                <tbody>
                    \(itemsHtml)
                </tbody>
            </table>
            <div class="totals">
                <p style="text-align: right; margin: 4px 0; font-size: 16px;"><strong>Total Due:</strong> \(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))</p>
            </div>
            <div class="footer">
                FireflyFM Official Billing Record
            </div>
        </body>
        </html>
        """

        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        printController.printPageRenderer = UIPrintPageRenderer()
        printController.printPageRenderer?.addPrintFormatter(formatter, startingAtPageAt: 0)
        printController.present(animated: true, completionHandler: nil)
    }
}
