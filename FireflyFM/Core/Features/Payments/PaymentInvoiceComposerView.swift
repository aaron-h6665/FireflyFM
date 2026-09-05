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
    @State private var lines = [ComposerLine()]
    @State private var validationMessage: String?
    @State private var idempotencyKey = "ios:zelle-invoice:\(UUID().uuidString)"

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
                    Text("The school can invoice only an approved parent linked to the selected child.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Invoice") {
                    TextField("Description", text: $memo)
                    DatePicker("Due date", selection: $dueDate, in: Date().addingTimeInterval(3600)...Date().addingTimeInterval(90 * 86400), displayedComponents: .date)
                    Text("Zelle invoices are one-time requests. Recurring or automatic payments are not supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    if let validationMessage { FireflyInlineError(message: validationMessage) }
                    if let errorMessage = model.errorMessage { FireflyInlineError(message: errorMessage) }
                }
            }
            .navigationTitle("New Zelle Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Issue") { issueInvoice() }.disabled(model.isMutating)
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
        lines.reduce(0) { $0 + Int64(max(0, PaymentAmountParser.cents(from: $1.amount)) * $1.quantity) }
    }

    private func issueInvoice() {
        guard policy.canManage, let parentId else {
            validationMessage = "Select the parent who is responsible for this invoice."
            return
        }
        let drafts = lines.compactMap { line -> ZelleInvoiceItemDraft? in
            let description = line.description.trimmed
            let amount = PaymentAmountParser.cents(from: line.amount)
            guard !description.isEmpty, amount >= 50 else { return nil }
            return ZelleInvoiceItemDraft(description: description, quantity: line.quantity, unitAmountCents: amount)
        }
        guard drafts.count == lines.count, !drafts.isEmpty else {
            validationMessage = "Every line needs a description and an amount of at least $0.50."
            return
        }
        guard !memo.trimmed.isEmpty else {
            validationMessage = "Add a short invoice description."
            return
        }
        validationMessage = nil
        let draft = ZelleInvoiceDraft(
            schoolId: schoolId,
            payerUserId: parentId,
            childId: childId,
            description: memo.trimmed,
            dueAt: Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: dueDate),
            items: drafts,
            idempotencyKey: idempotencyKey
        )
        Task {
            if await model.createInvoice(draft, policy: policy) {
                onCreated()
                dismiss()
            }
        }
    }
}

struct ZelleProfileEditorView: View {
    let schoolId: UUID
    let profile: SchoolZelleProfile?
    let model: PaymentsModel
    let policy: PaymentAccessPolicy
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var recipientDisplayName: String
    @State private var recipientType: ZelleRecipientType
    @State private var recipientValue: String
    @State private var memoPrefix: String
    @State private var instructions: String
    @State private var active: Bool
    @State private var betaSimulationEnabled: Bool
    @State private var validationMessage: String?

    init(
        schoolId: UUID,
        profile: SchoolZelleProfile?,
        model: PaymentsModel,
        policy: PaymentAccessPolicy,
        onSaved: @escaping () -> Void
    ) {
        self.schoolId = schoolId
        self.profile = profile
        self.model = model
        self.policy = policy
        self.onSaved = onSaved
        _recipientDisplayName = State(initialValue: profile?.recipientDisplayName ?? "")
        _recipientType = State(initialValue: profile?.recipientType ?? .email)
        _recipientValue = State(initialValue: profile?.recipientValue ?? "")
        _memoPrefix = State(initialValue: profile?.memoPrefix ?? "FF")
        _instructions = State(initialValue: profile?.paymentInstructions ?? "")
        _active = State(initialValue: profile?.active ?? false)
        _betaSimulationEnabled = State(initialValue: profile?.betaSimulationEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("School or recipient name", text: $recipientDisplayName)
                    Picker("Send using", selection: $recipientType) {
                        ForEach(ZelleRecipientType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField(recipientType == .email ? "Zelle email address" : "Zelle mobile number", text: $recipientValue)
                        .textInputAutocapitalization(.never)
                        .keyboardType(recipientType == .email ? .emailAddress : .phonePad)
                    TextField("Memo prefix", text: $memoPrefix)
                        .textInputAutocapitalization(.characters)
                    Text("Families will use a memo such as \(memoPrefix.trimmed.isEmpty ? "FF" : memoPrefix.trimmed.uppercased())-ZL-00000001. Do not enter bank login details or account numbers here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Instructions") {
                    TextField("Optional help for families", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Availability") {
                    Toggle("Accept new Zelle invoices", isOn: $active)
                    Toggle("Show beta simulation guidance", isOn: $betaSimulationEnabled)
                    Text("Simulation mode never sends money. It lets your team practice submitting and reviewing a test confirmation reference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Security boundary") {
                    Text("FireflyFM stores only the school’s Zelle recipient detail, invoice data, and a short confirmation reference. Directors must verify each transfer in the school’s bank experience before approving it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let validationMessage { FireflyInlineError(message: validationMessage) }
                if let errorMessage = model.errorMessage { FireflyInlineError(message: errorMessage) }
            }
            .navigationTitle("Zelle Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isMutating ? "Saving" : "Save") { save() }
                        .disabled(model.isMutating)
                }
            }
        }
    }

    private func save() {
        let normalizedMemo = memoPrefix.trimmed.uppercased()
        guard recipientDisplayName.trimmed.count >= 2,
              recipientValue.trimmed.count >= 4,
              normalizedMemo.range(of: "^[A-Z0-9-]{2,16}$", options: .regularExpression) != nil else {
            validationMessage = "Enter a recipient name, email or mobile number, and a 2–16 character letter/number memo prefix."
            return
        }
        validationMessage = nil
        let draft = ZelleProfileDraft(
            schoolId: schoolId,
            recipientDisplayName: recipientDisplayName.trimmed,
            recipientType: recipientType,
            recipientValue: recipientValue.trimmed,
            memoPrefix: normalizedMemo,
            paymentInstructions: instructions.nilIfBlank,
            active: active,
            betaSimulationEnabled: betaSimulationEnabled
        )
        Task {
            if await model.saveProfile(draft, policy: policy) {
                onSaved()
                dismiss()
            }
        }
    }
}

private struct ComposerLine: Identifiable {
    let id = UUID()
    var description = "Tuition"
    var amount = ""
    var quantity = 1
}

enum PaymentAmountParser {
    static func cents(from value: String) -> Int {
        let normalized = value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        guard let decimal = Decimal(string: normalized) else { return 0 }
        var amount = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
