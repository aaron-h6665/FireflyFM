import SwiftUI
import Supabase

struct PaymentsView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    var body: some View {
        if AppConfiguration.workspaceBetaEnabled { PaymentsBetaView().id(appSession.activeMembershipId) }
        else { LegacyPaymentsView() }
    }
}

struct PaymentsBetaView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var perspective: WorkspacePerspective = .manage
    @State private var bucket: WorkspaceBucket = .attention
    @State private var payerRole = SchoolRole.parent
    @State private var schoolOversight = false
    @State private var query = ""
    @State private var invoices: [ZelleInvoice] = []
    @State private var labels: [WorkspacePersonLabel] = []
    @State private var schools: [School] = []
    @State private var model = PaymentsModel()
    @State private var error: String?
    @State private var loading = false
    @State private var settings = false
    @State private var composer = false
    private var managing: Bool { appSession.workspaceManaging(perspective) }
    private var policy: PaymentAccessPolicy { PaymentAccessPolicy(context: appSession.accessContext()) }
    private var ownAttention: Int {
        invoices.filter { $0.payerUserId == appSession.profile?.id && WorkspaceBucket.payment($0.status, managing: false) == .attention }.count
    }
    private func name(_ invoice: ZelleInvoice) -> String {
        labels.first { $0.user_id == invoice.payerUserId && $0.school_id == invoice.schoolId }?.display_name ?? "Payer"
    }
    private func schoolName(_ id: UUID) -> String {
        schools.first { $0.id == id }?.name ?? appSession.activeSchool?.name ?? "School"
    }
    private var scoped: [ZelleInvoice] {
        invoices.filter { invoice in
            if !managing { return invoice.payerUserId == appSession.profile?.id }
            if invoice.payerUserId == appSession.profile?.id { return false }
            if appSession.role == .hqDirector && !schoolOversight { return invoice.payerRole == .schoolDirector }
            return invoice.payerRole == payerRole
        }
    }
    private var filtered: [ZelleInvoice] {
        scoped.filter {
            WorkspaceBucket.payment($0.status, managing: managing) == bucket
            && (query.isEmpty || name($0).localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query) || schoolName($0.schoolId).localizedCaseInsensitiveContains(query))
        }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }
    private var groups: [WorkspaceGroup<ZelleInvoice>] {
        Dictionary(grouping: filtered) { "\($0.schoolId):\($0.payerUserId)" }
            .map { WorkspaceGroup(id: $0.key, items: $0.value) }.sorted { left, right in
                guard let l = left.items.first, let r = right.items.first else { return false }
                return (schoolName(l.schoolId), name(l)) < (schoolName(r.schoolId), name(r))
            }
    }
    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if appSession.role == .schoolDirector && appSession.workspaceCanManage {
                        WorkspacePerspectivePicker(selection: $perspective, attentionCount: ownAttention)
                    }
                    if managing && (appSession.role != .hqDirector || schoolOversight) {
                        Picker("Payers", selection: $payerRole) {
                            Text("Parents").tag(SchoolRole.parent); Text("Teachers").tag(SchoolRole.teacher)
                        }.pickerStyle(.segmented)
                    }
                    if appSession.role == .hqDirector {
                        Text(schoolOversight ? "School payment oversight" : "School director payments").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(managing ? "Outstanding" : "Amount due")
                        Spacer()
                        Text(BillingMoney.string(cents: scoped.filter { ![.paid, .void, .expired].contains($0.status) }.reduce(0) { $0 + $1.amountRemainingCents })).bold()
                    }.font(.subheadline)
                    WorkspaceBucketPicker(selection: $bucket, managing: managing)
                    if loading { ProgressView("Loading payments…") }
                    if let error { FireflyInlineError(message: error) }
                    if filtered.isEmpty && !loading { FireflyEmptyState(title: "No payments here", message: "Invoices will appear here when assigned.", systemImage: "creditcard") }
                    WorkspaceList {
                        if managing {
                            ForEach(groups) { entry in
                                let group = entry.items
                                if let first = group.first {
                                    NavigationLink {
                                        PayerInvoiceList(invoices: group, payerName: name(first), schoolName: schoolName(first.schoolId))
                                    } label: {
                                        WorkspaceRow(title: name(first), subtitle: "\(schoolName(first.schoolId)) · \(group.count) invoice\(group.count == 1 ? "" : "s")", trailing: BillingMoney.string(cents: group.reduce(0) { $0 + ($1.status == .paid ? $1.amountPaidCents : $1.amountRemainingCents) }), symbol: "person.crop.circle")
                                    }.buttonStyle(.plain)
                                    Divider().padding(.leading, 44)
                                }
                            }
                        } else {
                            ForEach(filtered) { invoice in
                                NavigationLink { ZelleInvoiceDestinationView(invoiceId: invoice.id, schoolId: invoice.schoolId) }
                                label: { WorkspaceRow(title: invoice.description, subtitle: invoice.displayStatus, trailing: BillingMoney.string(cents: invoice.status == .paid ? invoice.amountPaidCents : invoice.amountRemainingCents), symbol: "creditcard") }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }.padding()
            }
        }
        .navigationTitle("Payments")
        .searchable(text: $query, prompt: managing ? "Search payers or schools" : "Search invoices")
        .toolbar {
            if managing {
                Menu {
                    Button("Receiving settings") { settings = true }
                    if appSession.role == .hqDirector {
                        Button(schoolOversight ? "Director payments" : "School payment oversight") { schoolOversight.toggle() }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                if appSession.role == .schoolDirector && payerRole == .parent {
                    Button { composer = true } label: { Label("New invoice", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $settings) {
            if appSession.role == .hqDirector { HQZelleSettingsView() }
            else if let id = appSession.activeSchool?.id {
                ZelleProfileEditorView(schoolId: id, profile: model.profile, model: model, policy: policy) { Task { await load() } }
            }
        }
        .sheet(isPresented: $composer) {
            if let id = appSession.activeSchool?.id {
                PaymentInvoiceComposerView(schoolId: id, parents: model.parents, children: [], model: model, policy: policy) { Task { await load() } }
            }
        }
        .task(id: appSession.activeMembershipId) { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let schoolId = appSession.role == .hqDirector ? nil : appSession.activeSchool?.id
            invoices = try await PaymentsClient.live.fetchInvoices(schoolId)
            struct Params: Encodable { let input_school_id: UUID? }
            labels = try await AppConstants.supabase.rpc("fetch_workspace_payer_labels", params: Params(input_school_id: schoolId)).execute().value
            if appSession.role == .hqDirector { schools = try await SchoolService.shared.fetchSchoolsForHQ() }
            if appSession.role == .schoolDirector && appSession.workspaceCanManage, let schoolId {
                await model.loadSchoolData(schoolId: schoolId)
            }
        } catch where AppErrorMessage.isCancellation(error) {} catch { self.error = AppErrorMessage.school("Could not load payments", error) }
    }
}

private struct PayerInvoiceList: View {
    let invoices: [ZelleInvoice]
    let payerName: String
    let schoolName: String
    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(schoolName).font(.subheadline).foregroundStyle(.secondary)
                    WorkspaceList {
                        ForEach(invoices) { invoice in
                            NavigationLink { ZelleInvoiceDestinationView(invoiceId: invoice.id, schoolId: invoice.schoolId) }
                            label: { WorkspaceRow(title: invoice.description, subtitle: invoice.displayStatus, trailing: BillingMoney.string(cents: invoice.amountDueCents), symbol: "creditcard") }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 44)
                        }
                    }
                }.padding()
            }
        }.navigationTitle(payerName)
    }
}
