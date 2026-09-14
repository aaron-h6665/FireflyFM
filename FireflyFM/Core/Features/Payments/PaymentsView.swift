import SwiftUI

struct PaymentsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var model = PaymentsModel()
    @State private var showsComposer = false
    @State private var showsZelleSettings = false
    @State private var selectedSchoolFilter: UUID? = nil

    private var policy: PaymentAccessPolicy {
        PaymentAccessPolicy(context: appSession.accessContext())
    }

    private var schoolId: UUID? { appSession.activeSchool?.id }

    private var effectiveSchoolId: UUID? {
        selectedSchoolFilter ?? schoolId ?? model.schools.first?.id
    }

    private var canCreateInvoice: Bool {
        guard !model.isMutating else { return false }
        if policy.hasCrossSchoolScope {
            return !model.schools.isEmpty
        }
        return model.profile?.active == true
    }

    private var displayedInvoices: [ZelleInvoice] {
        model.invoices(for: selectedSchoolFilter)
    }

    private var outstandingCents: Int64 {
        model.outstandingCents(for: selectedSchoolFilter)
    }

    private var collectedCents: Int64 {
        model.collectedCents(for: selectedSchoolFilter)
    }

    private var overdueCount: Int {
        model.overdueCount(for: selectedSchoolFilter)
    }

    var body: some View {
        FireflyScreen {
            Group {
                if !policy.canView {
                    FireflyEmptyState(
                        title: "Payments unavailable",
                        message: "Your school role does not include the billing workspace.",
                        systemImage: "lock.fill"
                    )
                    .padding()
                } else if model.phase.isLoading && model.invoices.isEmpty {
                    ProgressView("Loading payments…")
                } else {
                    content
                }
            }
        }
        .navigationTitle("Payments")
        .toolbar {
            if policy.canManageRecipientInstructions {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showsZelleSettings = true } label: {
                        Label("Zelle settings", systemImage: "gearshape")
                    }
                    if policy.canManage {
                        Button { showsComposer = true } label: {
                            Label("New Invoice", systemImage: "plus")
                        }
                        .disabled(!canCreateInvoice)
                    }
                }
            }
        }
        .sheet(isPresented: $showsZelleSettings) {
            if let targetSchoolId = effectiveSchoolId {
                ZelleProfileEditorView(
                    schoolId: targetSchoolId,
                    profile: model.profile,
                    model: model,
                    policy: policy
                ) { Task { await reload() } }
            }
        }
        .sheet(isPresented: $showsComposer) {
            if let targetSchoolId = effectiveSchoolId {
                PaymentInvoiceComposerView(
                    schoolId: targetSchoolId,
                    schools: model.schools,
                    parents: model.parents,
                    children: model.children,
                    model: model,
                    policy: policy
                ) { Task { await reload() } }
            }
        }
        .task(id: "\(appSession.activeMembershipId?.uuidString ?? "none")-\(appSession.role?.rawValue ?? "none")") {
            await reload()
        }
        .refreshable { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(FireflyTheme.Colors.secondaryText)

                if policy.hasCrossSchoolScope && model.schools.count > 1 {
                    schoolFilterSelector
                }

                if policy.hasCrossSchoolScope && selectedSchoolFilter == nil && !model.feeSummaries().isEmpty {
                    feesBySchoolCard
                }

                if policy.canManageRecipientInstructions, let targetId = (selectedSchoolFilter ?? (!policy.hasCrossSchoolScope ? schoolId : nil)) {
                    paymentSetupCard(schoolId: targetId)
                    if let school = appSession.activeSchool {
                        if appSession.role == .schoolDirector {
                            WorkspaceLink(
                                title: "Parent Onboarding Payments",
                                subtitle: "Add and manage required parent payment steps",
                                systemImage: "person.crop.circle.badge.checkmark",
                                destination: ParentOnboardingTimelineView(school: school, editingDomain: .payments)
                            )
                            WorkspaceLink(
                                title: "Teacher Onboarding Payments",
                                subtitle: "Manage payment requirements for teacher onboarding",
                                systemImage: "person.crop.circle.badge.checkmark",
                                destination: OnboardingTemplateBuilderView(school: school, role: .teacher, editingDomain: .payments)
                            )
                        } else if appSession.role == .hqDirector {
                            WorkspaceLink(
                                title: "Director Onboarding Payments",
                                subtitle: "Manage required school-director payment steps",
                                systemImage: "person.badge.key.fill",
                                destination: OnboardingTemplateBuilderView(school: school, role: .schoolDirector, editingDomain: .payments)
                            )
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    BillingSummaryCard(
                        title: policy.context.role == .parent ? "Amount due" : "Outstanding",
                        value: BillingMoney.string(cents: outstandingCents),
                        systemImage: "clock.badge.exclamationmark"
                    )
                    BillingSummaryCard(
                        title: "Verified paid",
                        value: BillingMoney.string(cents: collectedCents),
                        systemImage: "checkmark.circle.fill"
                    )
                }

                if overdueCount > 0 {
                    Label("\(overdueCount) overdue invoice\(overdueCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.bold())
                }

                if let errorMessage = model.errorMessage { FireflyInlineError(message: errorMessage) }

                HStack {
                    Text(selectedSchoolFilter != nil ? "Invoices (\(selectedSchoolName ?? "School"))" : "Invoices")
                        .font(.title3.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    Spacer()
                    if selectedSchoolFilter != nil {
                        Button("Show All") {
                            selectedSchoolFilter = nil
                        }
                        .font(.caption.bold())
                        .foregroundStyle(FireflyTheme.Colors.primaryAction)
                    }
                }

                if displayedInvoices.isEmpty {
                    FireflyEmptyState(
                        title: "No invoices yet",
                        message: policy.canManage ? "Set up the school’s Zelle instructions, then issue the first invoice." : "New invoices will appear here.",
                        systemImage: "doc.text"
                    )
                } else {
                    FireflySectionCard {
                        ForEach(Array(displayedInvoices.enumerated()), id: \.element.id) { index, invoice in
                            NavigationLink {
                                PaymentInvoiceDetailView(invoice: invoice, model: model, policy: policy) {
                                    Task { await reload() }
                                }
                            } label: {
                                BillingInvoiceRow(invoice: invoice, schoolName: schoolName(for: invoice.schoolId))
                            }
                            .buttonStyle(.plain)
                            if index < displayedInvoices.count - 1 { Divider() }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var selectedSchoolName: String? {
        guard let id = selectedSchoolFilter else { return nil }
        return model.schools.first(where: { $0.id == id })?.name
    }

    private var schoolFilterSelector: some View {
        HStack {
            Label("Filter School:", systemImage: "building.2")
                .font(.subheadline.bold())
                .foregroundStyle(FireflyTheme.Colors.secondaryText)
            Picker("School", selection: $selectedSchoolFilter) {
                Text("All Schools").tag(UUID?.none)
                ForEach(model.schools) { school in
                    Text(school.name).tag(UUID?.some(school.id))
                }
            }
            .pickerStyle(.menu)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var feesBySchoolCard: some View {
        FireflySectionCard {
            VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                HStack {
                    Text("Fees Collected by School")
                        .font(.headline)
                        .foregroundStyle(FireflyTheme.Colors.primaryText)
                    Spacer()
                    Text("\(model.feeSummaries().count) schools")
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                }

                ForEach(model.feeSummaries(), id: \.id) { summary in
                    Button {
                        selectedSchoolFilter = summary.school.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(summary.school.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(FireflyTheme.Colors.primaryText)
                                Spacer()
                                Text(BillingMoney.string(cents: summary.collectedCents))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(FireflyTheme.Colors.secondaryText)
                            }
                            HStack {
                                Text("\(summary.invoiceCount) invoice\(summary.invoiceCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(FireflyTheme.Colors.secondaryText)
                                if summary.outstandingCents > 0 {
                                    Text("• \(BillingMoney.string(cents: summary.outstandingCents)) pending")
                                        .font(.caption)
                                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                                }
                                if summary.overdueCount > 0 {
                                    Text("• \(summary.overdueCount) overdue")
                                        .font(.caption.bold())
                                        .foregroundStyle(.red)
                                }
                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    if summary.id != model.feeSummaries().last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var description: String {
        switch policy.context.role {
        case .parent: "Use your bank’s Zelle experience to send the exact invoice amount, then submit its confirmation reference for school review. FireflyFM never asks for bank credentials."
        case .schoolDirector: "Issue one-time invoices, give families the school’s Zelle instructions, and approve only transfers you verify in the school’s bank experience."
        case .hqDirector: "Monitor fees collected across all schools, issue school invoices, and generate official receipts."
        default: "School billing."
        }
    }

    private func paymentSetupCard(schoolId: UUID) -> some View {
        FireflySectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.profile?.active == true ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(model.profile?.active == true ? .green : .orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.profile?.active == true ? "Zelle instructions active" : "Zelle instructions need setup")
                        .font(.headline)
                    Text(setupDescription)
                        .font(.subheadline)
                        .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    Button(model.profile == nil ? "Set up Zelle instructions" : "Edit Zelle instructions") {
                        showsZelleSettings = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isMutating)
                }
            }
        }
    }

    private var setupDescription: String {
        guard let profile = model.profile else {
            return "Add the school’s Zelle recipient email or mobile number before issuing invoices or publishing an onboarding payment step."
        }
        if profile.active {
            return "Families send to \(profile.recipientDisplayName) using the protected instructions shown only on their own invoices."
        }
        return "The recipient detail is saved but not accepting new invoice requests yet."
    }

    private func schoolName(for id: UUID) -> String? {
        guard policy.hasCrossSchoolScope else { return nil }
        return model.schools.first(where: { $0.id == id })?.name ?? "School"
    }

    @MainActor
    private func reload() async {
        await model.load(schoolId: schoolId, policy: policy)
    }
}
