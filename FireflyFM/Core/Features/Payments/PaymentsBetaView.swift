import SwiftUI
import Supabase

struct PaymentsView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    var body: some View {
        if AppConfiguration.workspaceBetaEnabled { PaymentsBetaView().id("\(appSession.profile?.id.uuidString ?? ""):\(appSession.activeMembershipId?.uuidString ?? "")") }
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
    private enum Section: String, CaseIterable { case invoices, labels, schools, settings }
    private enum Payload { case invoices([ZelleInvoice]), labels([WorkspacePersonLabel]), schools([School]), settings(PaymentsModel) }
    @State private var loader = WorkspaceSectionLoader<Section, Payload>()
    private var scope: WorkspaceLoadScope { WorkspaceLoadScope(userId: appSession.profile?.id, membershipId: appSession.activeMembershipId, schoolId: appSession.activeSchool?.id) }
    private func value(_ section: Section) -> Payload? { loader.scope == scope ? loader.values[section] : nil }
    private var invoices: [ZelleInvoice] { if case .invoices(let rows) = value(.invoices) { return rows }; return [] }
    private var labels: [WorkspacePersonLabel] { if case .labels(let rows) = value(.labels) { return rows }; return [] }
    private var schools: [School] { if case .schools(let rows) = value(.schools) { return rows }; return [] }
    private var loading: Bool { loader.scope != scope || !loader.loading.isEmpty }
    @State private var model = PaymentsModel()
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
    private var bucketCounts: [WorkspaceBucket: Int] {
        Dictionary(grouping: scoped) { WorkspaceBucket.payment($0.status, managing: managing) }
            .mapValues(\.count)
    }
    private var outstandingCents: Int64 {
        scoped.filter { ![.paid, .void, .expired].contains($0.status) }
            .reduce(0) { $0 + $1.amountRemainingCents }
    }
    private var visibleSchoolIds: [UUID] {
        Array(Set(filtered.map(\.schoolId))).sorted { schoolName($0) < schoolName($1) }
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
                    HStack(spacing: 0) {
                        WorkspaceMetric(title: managing ? "To review" : "To do", value: "\(bucketCounts[.attention, default: 0])")
                        Divider().padding(.vertical, 2)
                        WorkspaceMetric(title: managing ? "Outstanding" : "Amount due", value: BillingMoney.string(cents: outstandingCents))
                    }
                    .padding(.vertical, 10)
                    .background(FireflyTheme.Colors.card, in: RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius))
                    WorkspaceBucketPicker(selection: $bucket, managing: managing, counts: bucketCounts)
                    if loading { ProgressView("Loading payments…") }
                    if loader.scope == scope {
                        ForEach(Section.allCases, id: \.self) { section in
                            if let error = loader.errors[section] {
                                VStack(alignment: .leading) {
                                    FireflyInlineError(message: error)
                                    Button("Retry \(section.rawValue)") { Task { await loadSection(section, scope: scope) } }
                                }
                            }
                        }
                    }
                    if value(.invoices) != nil && loader.errors[.invoices] == nil && !loader.loading.contains(.invoices) && filtered.isEmpty { FireflyEmptyState(title: "No payments here", message: "Invoices will appear here when assigned.", systemImage: "creditcard") }
                    paymentRows
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
        .task(id: scope) { await load() }
        .refreshable { await load() }
        .onChange(of: scope) { _, scope in loader.reset(to: scope); model = PaymentsModel() }
    }
    @ViewBuilder
    private var paymentRows: some View {
        if managing && appSession.role == .hqDirector {
            ForEach(visibleSchoolIds, id: \.self) { schoolId in
                Text(schoolName(schoolId).uppercased())
                    .font(FireflyTheme.Typography.badge)
                    .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    .padding(.top, 4)
                payerList(groups.filter { $0.items.first?.schoolId == schoolId })
            }
        } else if managing {
            payerList(groups)
        } else {
            WorkspaceList {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, invoice in
                    NavigationLink { ZelleInvoiceDestinationView(invoiceId: invoice.id, schoolId: invoice.schoolId) }
                    label: { WorkspaceRow(title: invoice.description, subtitle: invoice.displayStatus, trailing: BillingMoney.string(cents: invoice.status == .paid ? invoice.amountPaidCents : invoice.amountRemainingCents), symbol: "creditcard") }
                    .buttonStyle(.plain)
                    if index < filtered.count - 1 { Divider().padding(.leading, 44) }
                }
            }
        }
    }
    private func payerList(_ entries: [WorkspaceGroup<ZelleInvoice>]) -> some View {
        WorkspaceList {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let group = entry.items
                if let first = group.first {
                    NavigationLink {
                        PayerInvoiceList(invoices: group, payerName: name(first), schoolName: schoolName(first.schoolId))
                    } label: {
                        WorkspaceRow(
                            title: name(first),
                            subtitle: payerSubtitle(group),
                            trailing: BillingMoney.string(cents: group.reduce(0) { $0 + ($1.status == .paid ? $1.amountPaidCents : $1.amountRemainingCents) }),
                            symbol: "person.crop.circle"
                        )
                    }
                    .buttonStyle(.plain)
                    if index < entries.count - 1 { Divider().padding(.leading, 44) }
                }
            }
        }
    }
    private func payerSubtitle(_ invoices: [ZelleInvoice]) -> String {
        let count = "\(invoices.count) invoice\(invoices.count == 1 ? "" : "s")"
        switch bucket {
        case .attention:
            return "\(count) · \(invoices.count) to review"
        case .waiting:
            if let overdue = invoices.first(where: { $0.isPastDue }) { return "\(count) · \(overdue.displayStatus)" }
            if let due = invoices.compactMap(\.dueAt).min() {
                return "\(count) · Due \(due.formatted(date: .abbreviated, time: .omitted))"
            }
            return "\(count) · Waiting"
        case .history:
            return "\(count) · Done"
        }
    }
    private func load() async {
        let requestedScope = scope
        loader.reset(to: requestedScope)
        async let invoices: Void = loadSection(.invoices, scope: requestedScope)
        async let labels: Void = loadSection(.labels, scope: requestedScope)
        async let schools: Void = loadSection(.schools, scope: requestedScope)
        async let settings: Void = loadSection(.settings, scope: requestedScope)
        _ = await (invoices, labels, schools, settings)
    }
    private func loadSection(_ section: Section, scope requestedScope: WorkspaceLoadScope) async {
        guard requestedScope == scope else { return }
        let isHQ = appSession.role == .hqDirector
        let canManageSchool = appSession.role == .schoolDirector && appSession.workspaceCanManage
        await loader.load(section, scope: requestedScope, failureMessage: "Could not load payment \(section.rawValue)") {
            struct Params: Encodable { let input_school_id: UUID? }
            let schoolId = isHQ ? nil : requestedScope.schoolId
            switch section {
            case .invoices: return .invoices(try await PaymentsClient.live.fetchInvoices(schoolId))
            case .labels:
                let rows: [WorkspacePersonLabel] = try await AppConstants.supabase.rpc("fetch_workspace_payer_labels", params: Params(input_school_id: schoolId)).execute().value
                return .labels(rows)
            case .schools: return .schools(isHQ ? try await SchoolService.shared.fetchSchoolsForHQ() : [])
            case .settings:
                let loaded = PaymentsModel()
                if canManageSchool, let schoolId { await loaded.loadSchoolData(schoolId: schoolId) }
                if let error = loaded.errorMessage { throw NSError(domain: "Payments", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                return .settings(loaded)
            }
        }
        guard requestedScope == scope, !Task.isCancelled else { return }
        if section == .settings, case .settings(let loaded) = value(.settings) { model = loaded }
    }

}

private struct WorkspaceMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(FireflyTheme.Typography.supporting)
                .foregroundStyle(FireflyTheme.Colors.secondaryText)
            Text(value)
                .font(FireflyTheme.Typography.monetaryValue)
                .foregroundStyle(FireflyTheme.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
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
                        ForEach(Array(invoices.enumerated()), id: \.element.id) { index, invoice in
                            NavigationLink { ZelleInvoiceDestinationView(invoiceId: invoice.id, schoolId: invoice.schoolId) }
                            label: { WorkspaceRow(title: invoice.description, subtitle: invoice.displayStatus, trailing: BillingMoney.string(cents: invoice.amountDueCents), symbol: "creditcard") }
                            .buttonStyle(.plain)
                            if index < invoices.count - 1 { Divider().padding(.leading, 44) }
                        }
                    }
                }.padding()
            }
        }.navigationTitle(payerName)
    }
}
