#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import Supabase

private struct DemoBankTransfer: Decodable, Identifiable {
    let id: UUID
    let reference: String
    let amountCents: Int64
    let recipient: String
    let receivedAt: Date
    let received: Bool
    enum CodingKeys: String, CodingKey {
        case id, reference, recipient, received
        case amountCents = "amount_cents"
        case receivedAt = "received_at"
    }
}

@MainActor @Observable
private final class ZelleDemoLedgerModel {
    var transfers: [DemoBankTransfer] = []
    var error: String?
    var isLoading = false

    func load(_ invoiceId: UUID) async {
        guard AppConfiguration.paymentDemoEnabled else { return }
        do {
            transfers = try await AppConstants.supabase.from("zelle_demo_transfers").select()
                .eq("invoice_id", value: invoiceId).order("received_at", ascending: false).execute().value
        } catch { self.error = AppErrorMessage.school("Could not load demo bank", error) }
    }

    func generate(_ invoiceId: UUID, scenario: String) async {
        guard AppConfiguration.paymentDemoEnabled, !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let _: [DemoBankTransfer] = try await AppConstants.supabase.rpc("create_zelle_demo_transfer",
                params: ["input_invoice_id": invoiceId.uuidString, "input_scenario": scenario]).execute().value
            await load(invoiceId)
        } catch { self.error = AppErrorMessage.school("Could not generate demo transfer", error) }
    }
}

struct ZelleDemoLedgerView: View {
    let invoice: ZelleInvoice
    let policy: PaymentAccessPolicy
    @State private var model = ZelleDemoLedgerModel()

    var body: some View {
        FireflySectionCard {
            Text("DEMO bank — no money moved").font(.headline).foregroundStyle(.orange)
            if policy.canPay(invoice: invoice) && [.open, .rejected].contains(invoice.status) {
                Menu("Generate simulated transfer") {
                    Button("Matching payment") { generate("matching") }
                    Button("No received payment") { generate("missing") }
                    Button("Wrong amount") { generate("wrong_amount") }
                }.disabled(model.isLoading)
                Text("Copy a reference, then submit it above. To test duplicate detection, reuse that reference on another invoice.").font(.caption)
            }
            ForEach(model.transfers) { transfer in
                VStack(alignment: .leading, spacing: 5) {
                    Text(transfer.received ? "Received: \(BillingMoney.string(cents: transfer.amountCents))" : "Not received")
                    Text(transfer.recipient)
                    Text(transfer.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    Text(transfer.reference).textSelection(.enabled)
                    Button("Copy reference") { UIPasteboard.general.string = transfer.reference }
                }.font(.caption)
                Divider()
            }
            if model.transfers.isEmpty { Text("No simulated bank entries.").font(.caption) }
            if let error = model.error { FireflyInlineError(message: error) }
            Button("Refresh demo bank") { Task { await model.load(invoice.id) } }
        }
        .task(id: invoice.id) { await model.load(invoice.id) }
    }

    private func generate(_ scenario: String) {
        Task { await model.generate(invoice.id, scenario: scenario) }
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
/// Real Auth logins against the fixed local endpoint; never a role override.
struct PaymentDemoAccountMenu: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var isSwitching = false
    private let accounts = ["parent-a", "director-a", "teacher-a", "parent-b", "hq", "new-director"]
    var body: some View {
        HStack {
            Text("DEMO — no money moved").font(.caption.bold())
            Spacer()
            Menu("Demo account") {
                ForEach(accounts, id: \.self) { account in
                    Button(account) {
                        guard AppConfiguration.paymentDemoEnabled,
                              let password = ProcessInfo.processInfo.environment["FIREFLY_DEMO_PASSWORD"],
                              !password.isEmpty else { return }
                        isSwitching = true
                        Task {
                            await authManager.signOut()
                            await authManager.login(withEmail: "\(account)@payment-demo.example.test", password: password)
                            isSwitching = false
                        }
                    }
                }
            }.disabled(isSwitching || (ProcessInfo.processInfo.environment["FIREFLY_DEMO_PASSWORD"] ?? "").isEmpty)
        }
        .padding(8)
        .background(.orange.opacity(0.15))
    }
}
#endif
