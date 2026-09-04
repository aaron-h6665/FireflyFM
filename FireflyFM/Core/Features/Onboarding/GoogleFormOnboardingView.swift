import SwiftUI
import Observation
import AuthenticationServices
import UIKit

@MainActor
@Observable
final class GoogleFormOnboardingModel {
    private(set) var connections: [GoogleFormConnection] = []
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private(set) var notice: String?

    func load(schoolId: UUID, role: SchoolRole) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            connections = try await SchoolWorkflowService.shared.fetchGoogleFormConnections(schoolId: schoolId, role: role)
        } catch where AppErrorMessage.isCancellation(error) {} catch {
            errorMessage = AppErrorMessage.school("Could not load onboarding forms", error)
        }
    }

    func sync(schoolId: UUID, role: SchoolRole) async {
        isWorking = true
        errorMessage = nil
        notice = nil
        defer { isWorking = false }
        do {
            try await SchoolWorkflowService.shared.requestGoogleFormSync(
                schoolId: schoolId, role: role, connectionId: primaryConnection?.id
            )
            notice = "Sync requested. New responses will appear in the review queue when processing finishes."
            await load(schoolId: schoolId, role: role)
        } catch { errorMessage = AppErrorMessage.school("Could not start form sync", error) }
    }

    func disconnect(connectionId: UUID) async {
        isWorking = true
        errorMessage = nil
        do {
            try await SchoolWorkflowService.shared.disconnectGoogleForm(connectionId: connectionId)
            connections.removeAll { $0.id == connectionId }
            notice = "The form was removed from FireflyFM. The Google Drive form was not deleted."
        } catch { errorMessage = AppErrorMessage.school("Could not disconnect the form", error) }
        isWorking = false
    }

    func move(_ connection: GoogleFormConnection, direction: Int, role: SchoolRole) async {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        let target = index + direction
        guard connections.indices.contains(target) else { return }
        connections.swapAt(index, target)
        isWorking = true
        defer { isWorking = false }
        do {
            try await SchoolWorkflowService.shared.reorderGoogleForms(connections)
            await load(schoolId: connection.schoolId, role: role)
        } catch {
            errorMessage = AppErrorMessage.school("Could not reorder forms", error)
            await load(schoolId: connection.schoolId, role: role)
        }
    }

    var primaryConnection: GoogleFormConnection? {
        connections.first
    }

    static func formID(from value: String) -> String? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "docs.google.com",
              url.pathComponents.contains("forms") else { return nil }
        let components = url.pathComponents
        guard let formsIndex = components.firstIndex(of: "forms"), components.count > formsIndex + 2 else { return nil }
        let candidate = components[formsIndex + 2]
        return candidate == "edit" || candidate == "viewform" ? nil : candidate
    }
}

struct GoogleFormOnboardingView: View {
    let school: School
    let role: SchoolRole
    @State private var model = GoogleFormOnboardingModel()
    @State private var showingConnect = false
    @State private var showingRemoveConfirmation = false
    @State private var connectionToEdit: GoogleFormConnection?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    connectionCard
                    additionalForms
                    if let notice = model.notice { message(notice, color: .green) }
                    if let error = model.errorMessage { message(error, color: .red) }
                }
                .padding()
            }
            .refreshable { await model.load(schoolId: school.id, role: role) }
        }
        .navigationTitle(role == .parent ? "Parent Forms" : "Teacher Forms")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(schoolId: school.id, role: role) }
        .sheet(isPresented: $showingConnect) {
            GoogleFormConnectionSheet(school: school, role: role, existing: connectionToEdit, displayOrder: model.connections.count) {
                Task { await model.load(schoolId: school.id, role: role) }
            }
        }
        .confirmationDialog("Remove this form from FireflyFM?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            Button("Disconnect Form", role: .destructive) {
                if let connection = model.primaryConnection { Task { await model.disconnect(connectionId: connection.id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Google Form and its responses will remain in the director's Google account.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(school.name).font(.caption.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
            Text(role == .parent ? "Parent onboarding forms" : "Teacher onboarding forms").font(.largeTitle.bold()).foregroundColor(AppConstants.Colors.primaryText)
            Text("Connect Google to add forms, then arrange them in the order recipients should complete them.")
                .font(.subheadline).foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(role == .parent ? "Parent onboarding" : "Teacher onboarding", systemImage: "list.clipboard.fill").font(.headline)
                Spacer()
                Text(statusTitle(for: model.primaryConnection))
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(statusColor(for: model.primaryConnection).opacity(0.22))
                    .clipShape(Capsule())
            }
            if let connection = model.primaryConnection {
                Text(connection.formTitle ?? "Parent onboarding form").font(.title3.bold())
                Text(role == .parent ? "Child intake, health information, and required documents" : "Staff profile and required documents")
                    .font(.subheadline).foregroundColor(.secondary)
                if let email = connection.googleAccountEmail { Text(email).font(.caption).foregroundColor(.secondary) }
                if let synced = connection.lastSyncedAt { Text("Last synced \(synced.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundColor(.secondary) }
                HStack {
                    Button { Task { await model.sync(schoolId: school.id, role: role) } } label: { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.borderedProminent).tint(AppConstants.Colors.accessibleYellow)
                    Spacer()
                    Menu {
                        Button("Change Form") { connectionToEdit = model.primaryConnection; showingConnect = true }
                        Button("Connection details") { }
                        Divider()
                        Button("Disconnect Form", role: .destructive) { showingRemoveConfirmation = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .accessibilityLabel("Form actions")
                    }
                }
                .disabled(model.isWorking)
            } else {
                Text("Connect Google to add the first onboarding form.")
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.65))
                Button("Connect Google to Add Forms", systemImage: "link") { showingConnect = true }
                    .buttonStyle(.borderedProminent).tint(AppConstants.Colors.accessibleYellow)
            }
        }
        .padding().background(AppConstants.Colors.card).cornerRadius(10)
    }

    @ViewBuilder
    private var additionalForms: some View {
        let extras = model.connections.filter { $0.id != model.primaryConnection?.id }
        if extras.isEmpty == false {
            DisclosureGroup {
                ForEach(extras) { connection in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\((connection.displayOrder ?? 0) + 1). \(connection.formTitle ?? "Additional form")").font(.subheadline.bold())
                            Text(statusTitle(for: connection)).font(.caption).foregroundColor(statusColor(for: connection))
                        }
                        Spacer()
                        Menu {
                            Button("Edit form") { connectionToEdit = connection; showingConnect = true }
                            Button("Move up") { Task { await model.move(connection, direction: -1, role: role) } }
                            Button("Move down") { Task { await model.move(connection, direction: 1, role: role) } }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } label: {
                Text("Additional forms").font(.headline)
            }
            .padding().background(AppConstants.Colors.card).cornerRadius(10)
        }
        if model.primaryConnection != nil {
            Button("Add form") { connectionToEdit = nil; showingConnect = true }
                .font(.caption.bold())
                .padding(.leading, 4)
        }
    }

    private func statusTitle(for connection: GoogleFormConnection?) -> String {
        guard let connection else { return "Not connected" }
        switch connection.status {
        case "error": return "Needs attention"
        case "syncing": return "Syncing"
        default: return "Connected"
        }
    }

    private func statusColor(for connection: GoogleFormConnection?) -> Color {
        guard let connection else { return .secondary }
        return connection.status == "error" ? .orange : .green
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text).font(.caption).foregroundColor(color).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(AppConstants.Colors.card).cornerRadius(8)
    }
}

private struct GoogleFormConnectionSheet: View {
    let school: School
    let role: SchoolRole
    let existing: GoogleFormConnection?
    let displayOrder: Int
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var credential: GoogleFormsOAuthCompletion?
    @State private var forms: [GoogleAuthorizedForm] = []
    @State private var selectedForm: GoogleAuthorizedFormDetails?
    @State private var selectedQuestionByField: [String: String] = [:]
    @State private var requirements: [OnboardingTemplateRequirement] = []
    @State private var templateRequirementId: UUID?
    @State private var isRequired: Bool = true
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(school: School, role: SchoolRole, existing: GoogleFormConnection?, displayOrder: Int, onSaved: @escaping () -> Void) {
        self.school = school; self.role = role; self.existing = existing; self.displayOrder = displayOrder; self.onSaved = onSaved
        _isRequired = State(initialValue: existing?.isRequired ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                if credential == nil {
                    Section("Connect Google") {
                        Text("Sign in with the director-owned Google account that can read these Forms and their responses. FireflyFM stores only an encrypted refresh credential on the backend.")
                            .font(.caption).foregroundColor(.secondary)
                        Button("Connect Google Account", systemImage: "person.badge.key") {
                            Task { await connectGoogle() }
                        }
                        .disabled(isWorking)
                    }
                } else {
                    Section("Authorized Forms") {
                        Text(credential?.accountEmail ?? "Google connected")
                            .font(.caption).foregroundColor(.secondary)
                        if forms.isEmpty {
                            Text("No Google Forms were found in this account.").foregroundColor(.secondary)
                        } else {
                            ForEach(forms) { form in
                                Button {
                                    Task { await choose(form) }
                                } label: {
                                    HStack {
                                        Text(form.title)
                                        Spacer()
                                        if selectedForm?.id == form.id { Image(systemName: "checkmark").foregroundColor(.green) }
                                    }
                                }
                            }
                        }
                        Button("Use another Google account") {
                            credential = nil; forms = []; selectedForm = nil; selectedQuestionByField = [:]
                        }
                        .font(.caption)
                    }
                }

                if let form = selectedForm {
                    Section("Onboarding requirement") {
                        Toggle("Required for access", isOn: $isRequired)
                        if requirements.isEmpty {
                            Text("Publish an onboarding template requirement before making this Form required.")
                                .font(.caption).foregroundColor(.orange)
                        } else {
                            Picker("Completes requirement", selection: $templateRequirementId) {
                                Text("Choose requirement").tag(UUID?.none)
                                ForEach(requirements) { requirement in
                                    Text(requirement.title).tag(Optional(requirement.id))
                                }
                            }
                        }
                    }
                    Section(role == .parent ? "Parent intake mappings" : "Teacher form mapping") {
                        Text(role == .parent
                             ? "Map the child's identity and the hidden FireflyFM submission-reference question. The reference is prefilled for the invited parent and is never an invite secret."
                             : "Map the FireflyFM submission-reference question so this response is linked to the invited teacher.")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(mappingFields, id: \.key) { field in
                            Picker(field.title, selection: questionBinding(for: field.key)) {
                                Text("Not mapped").tag("")
                                ForEach(form.questions) { question in
                                    Text(question.title).tag(question.id)
                                }
                            }
                        }
                    }
                    Section("Selected Form") {
                        LabeledContent("Title", value: form.title)
                        LabeledContent("Questions", value: "\(form.questions.count)")
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundColor(.red) } }
            }
            .navigationTitle(existing == nil ? "Connect Form" : "Replace Form")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(selectedForm == nil || isWorking)
                }
            }
            .task { await loadRequirements() }
        }
    }

    private var mappingFields: [(key: String, title: String, required: Bool)] {
        let reference = (key: "submission_reference", title: "FireflyFM submission reference", required: true)
        guard role == .parent else { return [reference] }
        return [
            ("child_first_name", "Child first name", true),
            ("child_last_name", "Child last name", true),
            ("child_birthdate", "Child birthdate (YYYY-MM-DD)", true),
            ("relationship", "Parent/guardian relationship", true),
            ("respondent_email", "Parent email", true),
            reference,
            ("allergies", "Allergies", false),
            ("immunization_status", "Immunization status", false),
            ("physical_status", "Physical status", false),
            ("medicine_requirements", "Medication requirements", false),
            ("dietary_notes", "Dietary notes", false),
            ("emergency_contacts", "Emergency contacts (reviewed notes)", false),
        ]
    }

    private func questionBinding(for field: String) -> Binding<String> {
        Binding(
            get: { selectedQuestionByField[field, default: ""] },
            set: { selectedQuestionByField[field] = $0 }
        )
    }

    @MainActor
    private func connectGoogle() async {
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let start = try await SchoolWorkflowService.shared.startGoogleFormsOAuth(schoolId: school.id)
            guard let url = URL(string: start.authorizationURL) else { throw SchoolWorkflowError.invalidInput("Google returned an invalid authorization link.") }
            let callback = try await GoogleFormsWebAuthenticator.shared.authorize(url: url, callbackScheme: start.callbackScheme)
            let completed = try await SchoolWorkflowService.shared.completeGoogleFormsOAuth(schoolId: school.id, callbackURL: callback)
            credential = completed
            forms = try await SchoolWorkflowService.shared.fetchAuthorizedGoogleForms(schoolId: school.id, credentialId: completed.credentialId)
        } catch where AppErrorMessage.isCancellation(error) {} catch {
            errorMessage = AppErrorMessage.school("Could not connect Google", error)
        }
    }

    @MainActor
    private func choose(_ form: GoogleAuthorizedForm) async {
        guard let credential else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let details = try await SchoolWorkflowService.shared.inspectAuthorizedGoogleForm(
                schoolId: school.id, credentialId: credential.credentialId, formId: form.id
            )
            selectedForm = details
            selectedQuestionByField = defaultMappings(for: details)
        } catch { errorMessage = AppErrorMessage.school("Could not read Form questions", error) }
    }

    private func defaultMappings(for form: GoogleAuthorizedFormDetails) -> [String: String] {
        Dictionary(uniqueKeysWithValues: mappingFields.compactMap { field in
            let normalized = field.title.lowercased().replacingOccurrences(of: "fireflyfm ", with: "")
            guard let question = form.questions.first(where: { $0.title.lowercased().contains(normalized) }) else { return nil }
            return (field.key, question.id)
        })
    }

    @MainActor
    private func loadRequirements() async {
        do {
            requirements = try await SchoolWorkflowService.shared.fetchOnboardingTemplate(schoolId: school.id, role: role).requirements
        } catch { errorMessage = AppErrorMessage.school("Could not load onboarding requirements", error) }
    }

    @MainActor
    private func save() async {
        guard let credential, let form = selectedForm else { return }
        let requiredFields = mappingFields.filter { $0.required }
        if requiredFields.contains(where: { selectedQuestionByField[$0.key, default: ""].isEmpty }) {
            errorMessage = "Map every required Form field before saving."
            return
        }
        if isRequired && templateRequirementId == nil {
            errorMessage = "Choose the onboarding requirement this Form completes."
            return
        }
        let mappings = mappingFields.compactMap { field -> GoogleFormQuestionMapping? in
            guard let questionID = selectedQuestionByField[field.key], questionID.isEmpty == false,
                  let question = form.questions.first(where: { $0.id == questionID }) else { return nil }
            return GoogleFormQuestionMapping(questionId: question.id, questionTitle: question.title, fieldKey: field.key, required: field.required, active: true, prefillParameter: nil)
        }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await SchoolWorkflowService.shared.connectGoogleForm(
                schoolId: school.id, role: role, credentialId: credential.credentialId, form: form,
                formKey: existing?.formKey ?? form.id, mappings: mappings, templateRequirementId: templateRequirementId,
                isRequired: isRequired, displayOrder: existing?.displayOrder ?? displayOrder
            )
            onSaved(); dismiss()
        } catch { errorMessage = AppErrorMessage.school("Could not connect the Form", error) }
    }
}

@MainActor
private final class GoogleFormsWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleFormsWebAuthenticator()
    private var session: ASWebAuthenticationSession?

    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                self?.session = nil
                if let callbackURL { continuation.resume(returning: callbackURL) }
                else { continuation.resume(throwing: error ?? SchoolWorkflowError.invalidInput("Google authorization was cancelled.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if session.start() == false {
                self.session = nil
                continuation.resume(throwing: SchoolWorkflowError.invalidInput("Google authorization could not be started."))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
