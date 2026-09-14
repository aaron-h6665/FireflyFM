import SwiftUI

struct PaymentsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var model = PaymentsModel()
    @State private var showsComposer = false
    @State private var showsZelleSettings = false

    private var policy: PaymentAccessPolicy {
        PaymentAccessPolicy(context: appSession.accessContext())
    }

    private var schoolId: UUID? { appSession.activeSchool?.id }

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
                        .disabled(model.profile?.active != true || model.isMutating)
                    }
                }
            }
        }
        .sheet(isPresented: $showsZelleSettings) {
            if let schoolId {
                ZelleProfileEditorView(
                    schoolId: schoolId,
                    profile: model.profile,
                    model: model,
                    policy: policy
                ) { Task { await reload() } }
            }
        }
        .sheet(isPresented: $showsComposer) {
            if let schoolId {
                PaymentInvoiceComposerView(
                    schoolId: schoolId,
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

                if policy.canManageRecipientInstructions, let schoolId {
                    paymentSetupCard(schoolId: schoolId)
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
                        value: BillingMoney.string(cents: model.outstandingCents),
                        systemImage: "clock.badge.exclamationmark"
                    )
                    BillingSummaryCard(
                        title: "Verified paid",
                        value: BillingMoney.string(cents: model.collectedCents),
                        systemImage: "checkmark.circle.fill"
                    )
                }

                if model.overdueCount > 0 {
                    Label("\(model.overdueCount) overdue invoice\(model.overdueCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.bold())
                }

                if let errorMessage = model.errorMessage { FireflyInlineError(message: errorMessage) }

                Text("Invoices")
                    .font(.title3.bold())
                    .foregroundStyle(FireflyTheme.Colors.primaryText)

                if model.invoices.isEmpty {
                    FireflyEmptyState(
                        title: "No invoices yet",
                        message: policy.canManage ? "Set up the school’s Zelle instructions, then issue the first invoice." : "New invoices will appear here.",
                        systemImage: "doc.text"
                    )
                } else {
                    FireflySectionCard {
                        ForEach(Array(model.invoices.enumerated()), id: \.element.id) { index, invoice in
                            NavigationLink {
                                PaymentInvoiceDetailView(invoice: invoice, model: model, policy: policy) {
                                    Task { await reload() }
                                }
                            } label: {
                                BillingInvoiceRow(invoice: invoice, schoolName: schoolName(for: invoice.schoolId))
                            }
                            .buttonStyle(.plain)
                            if index < model.invoices.count - 1 { Divider() }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var description: String {
        switch policy.context.role {
        case .parent: "Use your bank’s Zelle experience to send the exact invoice amount, then submit its confirmation reference for school review. FireflyFM never asks for bank credentials."
        case .schoolDirector: "Issue one-time invoices, give families the school’s Zelle instructions, and approve only transfers you verify in the school’s bank experience."
        case .hqDirector: "Read cross-school payment records. HQ reviews only onboarding payments for new school directors; schools retain parent and teacher payment review."
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
