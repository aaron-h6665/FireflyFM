import SwiftUI
import UIKit

struct PaymentReceiptView: View {
    let invoice: ZelleInvoice
    let items: [ZelleInvoiceItem]
    let schoolName: String
    let reviewerName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    receiptDocument
                }
                .padding()
            }
            .background(FireflyTheme.Colors.background)
            .navigationTitle("Payment Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        ShareLink(
                            item: receiptText,
                            subject: Text("Receipt \(invoice.invoiceNumber) - \(schoolName)"),
                            message: Text("Payment receipt for \(invoice.invoiceNumber)")
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            printReceipt()
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                    }
                }
            }
        }
    }

    private var receiptDocument: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schoolName)
                        .font(.title2.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    Text("OFFICIAL PAYMENT RECEIPT")
                        .font(.caption.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryAction)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("PAID")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())

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
                    Text("Receipt Number:")
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    Text(invoice.invoiceNumber)
                        .font(.subheadline.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                }
                GridRow {
                    Text("Payment Date:")
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    Text(invoice.paidAt?.formatted(date: .long, time: .shortened) ?? "Recorded payment date")
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
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
                    Text("Subtotal")
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    Spacer()
                    Text(BillingMoney.string(cents: invoice.amountDueCents, currency: invoice.currency))
                }
                .font(.subheadline)

                HStack {
                    Text("Total Paid")
                        .font(.headline)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    Spacer()
                    Text(BillingMoney.string(cents: invoice.amountPaidCents, currency: invoice.currency))
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                }

                HStack {
                    Text("Balance Due")
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    Spacer()
                    Text("$0.00")
                        .fontWeight(.bold)
                }
                .font(.subheadline)
            }

            Divider()

            // Verification & settlement note
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Verified and settled in school billing records by \(reviewerName).")
                    .font(.caption)
                    .foregroundStyle(FireflyTheme.Colors.secondaryText)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(FireflyTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FireflyTheme.Colors.separator, lineWidth: 1)
        )
    }

    private var receiptText: String {
        var lines: [String] = []
        lines.append("========================================")
        lines.append(schoolName.uppercased())
        lines.append("OFFICIAL PAYMENT RECEIPT")
        lines.append("========================================")
        lines.append("Receipt Number: \(invoice.invoiceNumber)")
        lines.append("Payment Date: \(invoice.paidAt?.formatted(date: .long, time: .shortened) ?? "Recorded Date")")
        if let issuedAt = invoice.issuedAt {
            lines.append("Issue Date: \(issuedAt.formatted(date: .long, time: .omitted))")
        }
        lines.append("Description: \(invoice.description)")
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
        lines.append("TOTAL PAID: \(BillingMoney.string(cents: invoice.amountPaidCents, currency: invoice.currency))")
        lines.append("BALANCE DUE: $0.00")
        lines.append("Status: Paid & Verified")
        lines.append("Authorized Reviewer: \(reviewerName)")
        lines.append("========================================")
        return lines.joined(separator: "\n")
    }

    private func printReceipt() {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "Receipt-\(invoice.invoiceNumber)"
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
                .badge { color: #16a34a; font-weight: bold; font-size: 14px; text-transform: uppercase; }
                table { width: 100%; border-collapse: collapse; margin-top: 16px; margin-bottom: 16px; }
                th, td { padding: 8px 4px; text-align: left; border-bottom: 1px solid #e5e7eb; font-size: 13px; }
                th { color: #6b7280; font-weight: 600; }
                .totals { margin-top: 16px; border-top: 2px solid #333; padding-top: 12px; }
                .total-row { display: flex; justify-content: space-between; margin-bottom: 6px; font-size: 14px; }
                .total-paid { font-size: 18px; font-weight: bold; color: #16a34a; }
                .footer { margin-top: 28px; font-size: 11px; color: #6b7280; border-top: 1px solid #e5e7eb; padding-top: 10px; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>\(schoolName)</h1>
                <div class="badge">Official Payment Receipt &bull; Paid</div>
            </div>
            <div>
                <p><strong>Receipt #:</strong> \(invoice.invoiceNumber)</p>
                <p><strong>Date Paid:</strong> \(invoice.paidAt?.formatted(date: .long, time: .shortened) ?? "Recorded Date")</p>
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
                <p style="text-align: right; margin: 4px 0;"><strong>Total Paid:</strong> \(BillingMoney.string(cents: invoice.amountPaidCents, currency: invoice.currency))</p>
                <p style="text-align: right; margin: 4px 0; color: #6b7280;"><strong>Balance Due:</strong> $0.00</p>
            </div>
            <div class="footer">
                Verified and settled in school billing records by \(reviewerName). FireflyFM Official Billing Record.
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
