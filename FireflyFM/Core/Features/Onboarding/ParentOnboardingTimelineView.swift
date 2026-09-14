import SwiftUI
import Observation

@MainActor
@Observable
final class ParentOnboardingTimelineModel {
    private(set) var template: OnboardingTemplate?
    private(set) var steps: [ParentOnboardingTimelineEditorItem] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var notice: String?

    func load(schoolId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            template = try await SchoolWorkflowService.shared.ensureOnboardingTemplateDraft(schoolId: schoolId, role: .parent)
            steps = try await SchoolWorkflowService.shared.fetchParentOnboardingTimelineEditor(schoolId: schoolId)
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not load the parent onboarding timeline", error)
        }
    }

    func addForm(
        schoolId: UUID,
        credential: GoogleFormsOAuthCompletion,
        form: GoogleAuthorizedFormDetails
    ) async -> Bool {
        guard let template else { return false }
        guard !steps.contains(where: { $0.formId == form.id }) else {
            errorMessage = "That Form is already in this timeline."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let requirement = try await SchoolWorkflowService.shared.saveOnboardingTemplateRequirement(
                templateId: template.id,
                requirementId: nil,
                title: form.title,
                description: "Complete this Form in FireflyFM.",
                subjectScope: .member,
                position: steps.count,
                attachments: [],
                blocksAccess: true,
                childRecordBinding: .none,
                requirementType: .document
            )
            do {
                _ = try await SchoolWorkflowService.shared.connectGoogleForm(
                    schoolId: schoolId,
                    role: .parent,
                    credentialId: credential.credentialId,
                    form: form,
                    // A timeline requirement owns a versioned connection. This
                    // lets a later draft reuse the same Google Form without
                    // changing the snapshot received by earlier invitees.
                    formKey: "\(form.id):\(requirement.id.uuidString)",
                    displayOrder: steps.count,
                    templateRequirementId: requirement.id
                )
            } catch {
                try? await SchoolWorkflowService.shared.removeOnboardingTemplateRequirement(requirementId: requirement.id)
                throw error
            }
            notice = "Added \(form.title). FireflyFM prepared its private routing automatically."
            await reloadSteps(schoolId: schoolId)
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not add this Form", error)
            return false
        }
    }

    func savePayment(schoolId: UUID, item: ParentOnboardingTimelineEditorItem?, title: String, amount: Int64, dueDays: Int) async -> Bool {
        guard let template else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await SchoolWorkflowService.shared.saveOnboardingTemplateRequirement(
                templateId: template.id,
                requirementId: item?.requirementId,
                title: title,
                description: "Send the payment using the school’s instructions, then submit the confirmation for review.",
                subjectScope: .member,
                position: item?.position ?? steps.count,
                attachments: [],
                blocksAccess: true,
                childRecordBinding: .none,
                requirementType: .payment,
                paymentAmountCents: amount,
                paymentDueDays: dueDays
            )
            notice = item == nil ? "Payment step added." : "Payment step updated."
            await reloadSteps(schoolId: schoolId)
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not save the payment step", error)
            return false
        }
    }

    func move(_ reordered: [ParentOnboardingTimelineEditorItem], schoolId: UUID) async {
        guard let template else { return }
        steps = reordered
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await SchoolWorkflowService.shared.reorderOnboardingTemplateRequirements(
                templateId: template.id,
                requirementIds: reordered.map(\.requirementId)
            )
            await reloadSteps(schoolId: schoolId)
        } catch {
            errorMessage = AppErrorMessage.school("Could not reorder the timeline", error)
            await reloadSteps(schoolId: schoolId)
        }
    }

    func remove(_ item: ParentOnboardingTimelineEditorItem, schoolId: UUID) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await SchoolWorkflowService.shared.removeParentOnboardingTimelineStep(requirementId: item.requirementId)
            notice = item.isForm ? "Form removed from the timeline." : "Payment step removed from the timeline."
            await reloadSteps(schoolId: schoolId)
        } catch {
            errorMessage = AppErrorMessage.school("Could not remove this step", error)
        }
    }

    func publish(schoolId: UUID) async {
        guard let template else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await SchoolWorkflowService.shared.publishOnboardingTemplate(templateId: template.id)
            notice = "Published. Future parent invitations receive this timeline."
            await load(schoolId: schoolId)
        } catch {
            errorMessage = AppErrorMessage.school("Could not publish the parent timeline", error)
        }
    }

    private func reloadSteps(schoolId: UUID) async {
        do {
            steps = try await SchoolWorkflowService.shared.fetchParentOnboardingTimelineEditor(schoolId: schoolId)
        } catch {
            errorMessage = AppErrorMessage.school("Could not refresh the parent timeline", error)
        }
    }
}

struct ParentOnboardingTimelineView: View {
    let school: School
    let editingDomain: OnboardingWorkspaceDomain
    @State private var model = ParentOnboardingTimelineModel()
    @State private var showingFormPicker = false
    @State private var paymentToEdit: ParentOnboardingTimelineEditorItem?
    @State private var showingPaymentEditor = false
    @State private var stepToRemove: ParentOnboardingTimelineEditorItem?

    init(school: School, editingDomain: OnboardingWorkspaceDomain = .all) {
        self.school = school
        self.editingDomain = editingDomain
    }

    private var visibleSteps: [ParentOnboardingTimelineEditorItem] {
        model.steps.filter { item in
            switch editingDomain {
            case .all: true
            case .paperwork: !item.isPayment
            case .payments: item.isPayment
            }
        }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            List {
                Section {
                    header
                }
                .listRowBackground(AppConstants.Colors.card)

                Section("Parent timeline") {
                    if model.isLoading && visibleSteps.isEmpty {
                        ProgressView("Preparing parent onboarding")
                    } else if visibleSteps.isEmpty {
                        ContentUnavailableView(
                            editingDomain == .payments ? "No onboarding payment" : "Start with a Form",
                            systemImage: editingDomain == .payments ? "dollarsign.circle" : "doc.badge.plus",
                            description: Text(editingDomain == .payments
                                              ? "Add and manage parent onboarding payment steps from Payments."
                                              : "Choose the first Form parents complete. FireflyFM handles the private routing field for you.")
                        )
                    } else {
                        ForEach(visibleSteps) { item in
                            timelineRow(item)
                        }
                        .onMove(perform: editingDomain == .all ? move : nil)
                    }
                }
                .listRowBackground(AppConstants.Colors.card)

                Section {
                    if editingDomain != .payments {
                        Button {
                            showingFormPicker = true
                        } label: {
                            Label("Add Form", systemImage: "doc.badge.plus")
                        }
                        .disabled(model.isSaving)
                    }

                    if editingDomain != .paperwork {
                        Button {
                            paymentToEdit = nil
                            showingPaymentEditor = true
                        } label: {
                            Label("Add Onboarding Payment", systemImage: "dollarsign.circle")
                        }
                        .disabled(model.isSaving)
                    }

                    if editingDomain != .paperwork {
                        NavigationLink {
                            PaymentsView()
                        } label: {
                            Label("Set Payment Instructions", systemImage: "building.columns")
                        }
                    }

                    if model.steps.contains(where: { $0.isForm && $0.formStatus != "connected" }) {
                        NavigationLink {
                            GoogleAccountConnectionView(school: school)
                        } label: {
                            Label("Reconnect Google to finish setup", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    if model.template?.status == .draft {
                        Button {
                            Task { await model.publish(schoolId: school.id) }
                        } label: {
                            Label(model.isSaving ? "Publishing" : "Publish Parent Timeline", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(model.steps.filter(\.isForm).isEmpty || model.isSaving)
                    }
                }
                .listRowBackground(AppConstants.Colors.card)

                if let notice = model.notice {
                    Text(notice).foregroundStyle(.green).listRowBackground(AppConstants.Colors.card)
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red).listRowBackground(AppConstants.Colors.card)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Parent Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editingDomain == .all && model.steps.count > 1 && model.template?.status == .draft {
                EditButton()
            }
        }
        .task { await model.load(schoolId: school.id) }
        .sheet(isPresented: $showingFormPicker) {
            ParentTimelineFormPickerSheet(school: school) { credential, form in
                await model.addForm(schoolId: school.id, credential: credential, form: form)
            }
        }
        .sheet(isPresented: $showingPaymentEditor, onDismiss: {
            paymentToEdit = nil
        }) {
            ParentTimelinePaymentSheet(item: paymentToEdit) { title, amount, dueDays in
                await model.savePayment(
                    schoolId: school.id,
                    item: paymentToEdit,
                    title: title,
                    amount: amount,
                    dueDays: dueDays
                )
            }
        }
        .confirmationDialog(
            "Remove \(stepToRemove?.title ?? "this step")?",
            isPresented: Binding(get: { stepToRemove != nil }, set: { if !$0 { stepToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let stepToRemove else { return }
                Task { await model.remove(stepToRemove, schoolId: school.id) }
            }
            Button("Cancel", role: .cancel) { stepToRemove = nil }
        } message: {
            Text("This changes only the draft timeline. Parents already in onboarding keep their current steps.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(school.name).font(.caption.bold()).foregroundStyle(AppConstants.Colors.accessibleYellow)
                Spacer()
                Text(model.template?.status.title ?? "Draft")
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                    .background((model.template?.status == .published ? Color.green : Color.orange).opacity(0.22))
                    .clipShape(Capsule())
            }
            Text(headerTitle)
                .font(.title3.bold())
            Text(headerDescription)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func timelineRow(_ item: ParentOnboardingTimelineEditorItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(item.position + 1)")
                .font(.caption.bold()).foregroundStyle(AppConstants.Colors.brandNavy)
                .frame(width: 26, height: 26).background(AppConstants.Colors.accessibleYellow).clipShape(Circle())
            Image(systemName: item.isForm ? "doc.text.fill" : item.isPayment ? "dollarsign.circle.fill" : "doc.text")
                .foregroundStyle(item.isPayment ? Color.green : AppConstants.Colors.accessibleYellow)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.isForm ? (item.formTitle ?? item.title) : item.title).font(.headline)
                if item.isForm {
                    Text("Form · \(item.googleAccountEmail ?? "Google account")")
                        .font(.caption).foregroundStyle(.secondary)
                } else if item.isPayment, let amount = item.paymentAmountCents {
                    Text("Payment · \(BillingMoney.string(cents: amount)) · due in \(item.paymentDueDays ?? 7) days")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(item.description ?? "Paperwork")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let warning = item.setupWarning, !warning.isEmpty {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Menu {
                if item.isPayment && editingDomain != .paperwork {
                    Button("Edit Payment") {
                        paymentToEdit = item
                        showingPaymentEditor = true
                    }
                }
                Button("Remove", role: .destructive) { stepToRemove = item }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var headerTitle: String {
        switch editingDomain {
        case .all: "One simple plan for every parent"
        case .paperwork: "Parent onboarding paperwork"
        case .payments: "Parent onboarding payments"
        }
    }

    private var headerDescription: String {
        switch editingDomain {
        case .all: "Order Paperwork and Payment steps, then publish one onboarding plan."
        case .paperwork: "Choose Forms and paperwork here. Payment steps are managed only in Payments."
        case .payments: "Add or edit onboarding payment steps here. Forms and documents stay in Paperwork."
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = model.steps
        reordered.move(fromOffsets: source, toOffset: destination)
        Task { await model.move(reordered, schoolId: school.id) }
    }
}

private struct ParentTimelinePaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ParentOnboardingTimelineEditorItem?
    let onSave: (String, Int64, Int) async -> Bool
    @State private var title: String
    @State private var amount: String
    @State private var dueDays: Int
    @State private var isSaving = false
    @State private var error: String?

    init(item: ParentOnboardingTimelineEditorItem?, onSave: @escaping (String, Int64, Int) async -> Bool) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item?.title ?? "Onboarding payment")
        _amount = State(initialValue: item?.paymentAmountCents.map { BillingMoney.string(cents: $0) } ?? "")
        _dueDays = State(initialValue: item?.paymentDueDays ?? 7)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Required payment") {
                    TextField("Name", text: $title)
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    Stepper("Due within \(dueDays) day\(dueDays == 1 ? "" : "s")", value: $dueDays, in: 1...90)
                }
                Section {
                    Text("One designated parent receives this payment. FireflyFM shows the school’s Zelle instructions, collects a confirmation reference, and waits for the school to verify it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(item == nil ? "Add Payment" : "Edit Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let cents = PaymentAmountParser.cents(from: amount)
        guard cents >= 50 else { error = "Enter an amount of at least $0.50."; return }
        isSaving = true
        Task {
            let saved = await onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), Int64(cents), dueDays)
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct ParentTimelineFormPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let school: School
    let onSelected: (GoogleFormsOAuthCompletion, GoogleAuthorizedFormDetails) async -> Bool
    @State private var credentials: [GoogleFormsOAuthCompletion] = []
    @State private var credential: GoogleFormsOAuthCompletion?
    @State private var forms: [GoogleAuthorizedForm] = []
    @State private var selectedSource: GoogleAuthorizedForm?
    @State private var selectedForm: GoogleAuthorizedFormDetails?
    @State private var search = ""
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var error: String?
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("Loading Google Forms")
                } else if credential == nil {
                    Section("Connect Google") {
                        Text("Connect the director-owned account that has the Forms you want parents to complete.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Connect Google") { Task { await connectGoogle() } }
                    }
                } else if let previewedForm = selectedForm, let previewedSource = selectedSource {
                    Section("Preview") {
                        Label(previewedForm.title, systemImage: "doc.text.fill").font(.headline)
                        LabeledContent("Google account", value: previewedForm.accountEmail)
                        LabeledContent("Questions", value: "\(previewedForm.questions.count)")
                        ForEach(previewedForm.questions.prefix(8)) { question in
                            Text(question.title).font(.subheadline)
                        }
                        if previewedForm.questions.count > 8 {
                            let remainingQuestionCount = previewedForm.questions.count - 8
                            Text("Plus \(remainingQuestionCount) more questions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let value = previewedSource.editURL, let url = URL(string: value) {
                            Button("Open Original Form") { previewURL = url }
                        }
                        Text("When added, FireflyFM automatically prepares its private routing field. Parents do not need to enter that value.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Choose a Different Form") { selectedForm = nil; selectedSource = nil }
                } else {
                    Section("Google account") {
                        Picker("Account", selection: $credential) {
                            ForEach(credentials, id: \.credentialId) { account in
                                Text(account.accountEmail).tag(Optional(account))
                            }
                        }
                        .onChange(of: credential) { _, _ in Task { await loadForms() } }
                    }
                    Section("Choose a Form") {
                        if filteredForms.isEmpty {
                            Text("No Forms were found in this account.").foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredForms) { form in
                                Button { Task { await inspect(form) } } label: {
                                    HStack { Text(form.title); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                                }
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Add Parent Form")
            .searchable(text: $search, prompt: "Search Google Forms")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if let credential, let selectedForm {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isWorking ? "Adding" : "Add to Timeline") {
                            Task {
                                isWorking = true
                                let saved = await onSelected(credential, selectedForm)
                                isWorking = false
                                if saved { dismiss() }
                            }
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .task { await loadCredentials() }
            .sheet(item: Binding(get: { previewURL.map(FormPreviewRoute.init) }, set: { if $0 == nil { previewURL = nil } })) { route in
                FireflySafariView(url: route.url).ignoresSafeArea()
            }
        }
    }

    private var filteredForms: [GoogleAuthorizedForm] {
        let value = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? forms : forms.filter { $0.title.localizedCaseInsensitiveContains(value) }
    }

    private func loadCredentials() async {
        isLoading = true
        defer { isLoading = false }
        do {
            credentials = try await SchoolWorkflowService.shared.fetchGoogleFormsOAuthCredentials(schoolId: school.id)
            credential = credentials.first
            await loadForms()
        } catch { self.error = AppErrorMessage.school("Could not load Google Forms", error) }
    }

    private func loadForms() async {
        guard let credential else { forms = []; return }
        isWorking = true
        defer { isWorking = false }
        do {
            forms = try await SchoolWorkflowService.shared.fetchAuthorizedGoogleForms(schoolId: school.id, credentialId: credential.credentialId)
            selectedForm = nil; selectedSource = nil
        } catch { self.error = AppErrorMessage.school("Could not load this account’s Forms", error) }
    }

    private func inspect(_ form: GoogleAuthorizedForm) async {
        guard let credential else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            selectedForm = try await SchoolWorkflowService.shared.inspectAuthorizedGoogleForm(schoolId: school.id, credentialId: credential.credentialId, formId: form.id)
            selectedSource = form
        } catch { self.error = AppErrorMessage.school("Could not preview this Form", error) }
    }

    private func connectGoogle() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let start = try await SchoolWorkflowService.shared.startGoogleFormsOAuth(schoolId: school.id)
            guard let url = URL(string: start.authorizationURL) else { throw SchoolWorkflowError.invalidInput("Google returned an invalid authorization link.") }
            let callback = try await GoogleFormsWebAuthenticator.shared.authorize(url: url, callbackScheme: start.callbackScheme)
            let complete = try await SchoolWorkflowService.shared.completeGoogleFormsOAuth(schoolId: school.id, callbackURL: callback)
            credentials = try await SchoolWorkflowService.shared.fetchGoogleFormsOAuthCredentials(schoolId: school.id)
            credential = credentials.first(where: { $0.credentialId == complete.credentialId })
            await loadForms()
        } catch where AppErrorMessage.isCancellation(error) {
        } catch { self.error = AppErrorMessage.school("Could not connect Google", error) }
    }
}

private struct FormPreviewRoute: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
