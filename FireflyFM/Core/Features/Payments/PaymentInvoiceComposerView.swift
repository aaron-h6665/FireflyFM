import SwiftUI

struct PaymentInvoiceComposerView: View {
    let schoolId: UUID
    let parents: [SchoolMember]
    let children: [Child]
    let model: PaymentsModel
    let policy: PaymentAccessPolicy
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var parentId: UUID?
    @State private var childId: UUID?
    @State private var memo = "Childcare tuition"
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var recurrence: BillingRecurrence = .once
    @State private var lines = [ComposerLine()]
    @State private var validationMessage: String?
    @State private var idempotencyKey = "ios:create:\(UUID().uuidString)"

    var body: some View {
        NavigationStack {
            Form {
                Section("Payer") {
                    Picker("Parent", selection: $parentId) {
                        Text("Select a parent").tag(Optional<UUID>.none)
                        ForEach(parents) { parent in
                            Text(parent.displayName).tag(Optional(parent.id))
                        }
                    }
                    Picker("Child (optional)", selection: $childId) {
                        Text("No child selected").tag(Optional<UUID>.none)
                        ForEach(children) { child in
                            Text(child.fullName).tag(Optional(child.id))
                        }
                    }
                    Text("The server verifies that the selected parent is an active, verified guardian for the child.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Invoice") {
                    TextField("Memo", text: $memo)
                    DatePicker("Due date", selection: $dueDate, in: Date().addingTimeInterval(3600)...Date().addingTimeInterval(90 * 86400), displayedComponents: .date)
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(BillingRecurrence.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }

                Section("Line items") {
                    ForEach($lines) { $line in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Description", text: $line.description)
                            HStack {
                                TextField("Amount", text: $line.amount)
                                    .keyboardType(.decimalPad)
                                Stepper("Qty \(line.quantity)", value: $line.quantity, in: 1...100)
                            }
                        }
                    }
                    .onDelete { offsets in
                        lines.remove(atOffsets: offsets)
                        if lines.isEmpty { lines = [ComposerLine()] }
                    }
                    Button("Add line item", systemImage: "plus") {
                        if lines.count < 20 { lines.append(ComposerLine()) }
                    }
                }

                Section {
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(BillingMoney.string(cents: totalCents))
                            .fontWeight(.bold)
                    }
                    if let validationMessage {
                        FireflyInlineError(message: validationMessage)
                    }
                    if let errorMessage = model.errorMessage {
                        FireflyInlineError(message: errorMessage)
                    }
                }
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Issue") { issueInvoice() }
                        .disabled(model.isMutating)
                }
            }
            .overlay {
                if model.isMutating {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        ProgressView("Creating invoice…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var totalCents: Int64 {
        lines.reduce(0) { partial, line in
            partial + Int64(max(0, cents(from: line.amount)) * line.quantity)
        }
    }

    private func issueInvoice() {
        guard policy.canManage, let parentId else {
            validationMessage = "Select the parent who is responsible for this invoice."
            return
        }
        let drafts = lines.compactMap { line -> BillingLineItemDraft? in
            let description = line.description.trimmed
            let amount = cents(from: line.amount)
            guard !description.isEmpty, amount >= 50 else { return nil }
            return BillingLineItemDraft(description: description, quantity: line.quantity, unitAmountCents: amount)
        }
        guard drafts.count == lines.count, !drafts.isEmpty else {
            validationMessage = "Every line needs a description and an amount of at least $0.50."
            return
        }
        validationMessage = nil
        let draft = BillingInvoiceDraft(
            schoolId: schoolId,
            parentUserId: parentId,
            childId: childId,
            lineItems: drafts,
            dueDate: dueDate,
            recurrence: recurrence,
            memo: memo.nilIfBlank,
            // Keep the same key for retries while this composer is open so a
            // lost response cannot create a second Stripe invoice.
            idempotencyKey: idempotencyKey
        )
        Task {
            if await model.createInvoice(draft, policy: policy) {
                onCreated()
                dismiss()
            }
        }
    }

    private func cents(from value: String) -> Int {
        let normalized = value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        guard let decimal = Decimal(string: normalized) else { return 0 }
        var amount = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

private struct ComposerLine: Identifiable {
    let id = UUID()
    var description = "Tuition"
    var amount = ""
    var quantity = 1
}
