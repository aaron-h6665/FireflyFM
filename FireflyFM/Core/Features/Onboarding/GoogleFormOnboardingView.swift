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
                schoolId: schoolId, role: role, connectionId: nil
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
    @State private var connectionToRemove: GoogleFormConnection?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    onboardingSequence
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
            GoogleFormConnectionSheet(school: school, role: role, existing: connectionToEdit, displayOrder: nextDisplayOrder) {
                Task { await model.load(schoolId: school.id, role: role) }
            }
        }
        .confirmationDialog("Remove this form from FireflyFM?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove Form", role: .destructive) {
                if let connection = connectionToRemove { Task { await model.disconnect(connectionId: connection.id) } }
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
            Text("Add the school’s Forms once. Parents and teachers receive one Form at a time, in the sequence you set here.")
                .font(.subheadline).foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
        }
    }

    private var nextDisplayOrder: Int {
        (model.connections.compactMap(\.displayOrder).max() ?? -1) + 1
    }

    private var onboardingSequence: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Onboarding sequence", systemImage: "list.number").font(.headline)
                Spacer()
                if model.connections.isEmpty == false {
                    Button { Task { await model.sync(schoolId: school.id, role: role) } } label: {
                        Label("Sync all", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .font(.caption.bold())
                    .disabled(model.isWorking)
                }
            }
            Text("A submission checks off its onboarding step only after the school reviews it. FireflyFM recognizes the standard intake questions automatically.")
                .font(.caption).foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))

            if model.connections.isEmpty {
                ContentUnavailableView(
                    "No Forms yet",
                    systemImage: "doc.badge.plus",
                    description: Text("Connect Google, then choose the first Form recipients should complete.")
                )
                Button("Add first Form", systemImage: "plus") {
                    connectionToEdit = nil; showingConnect = true
                }
                .buttonStyle(.borderedProminent).tint(AppConstants.Colors.accessibleYellow)
            } else {
                ForEach(Array(model.connections.enumerated()), id: \.element.id) { index, connection in
                    if index > 0 { Divider() }
                    sequenceRow(connection, position: index)
                }
                Button("Add another Form", systemImage: "plus") {
                    connectionToEdit = nil; showingConnect = true
                }
                .buttonStyle(.bordered)
                .tint(AppConstants.Colors.accessibleYellow)
            }
        }
        .padding().background(AppConstants.Colors.card).cornerRadius(10)
    }

    private func sequenceRow(_ connection: GoogleFormConnection, position: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(position + 1)")
                .font(.caption.bold()).foregroundColor(AppConstants.Colors.brandNavy)
                .frame(width: 26, height: 26).background(AppConstants.Colors.accessibleYellow).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.formTitle ?? "Onboarding Form").font(.subheadline.bold())
                Text(sequenceDescription(position: position))
                    .font(.caption).foregroundColor(AppConstants.Colors.primaryText.opacity(0.6))
                if connection.status == "error" {
                    Text(connection.lastError ?? "Needs attention")
                        .font(.caption).foregroundColor(.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button("Replace Form") { connectionToEdit = connection; showingConnect = true }
                if position > 0 {
                    Button("Move earlier") { Task { await model.move(connection, direction: -1, role: role) } }
                }
                if position < model.connections.count - 1 {
                    Button("Move later") { Task { await model.move(connection, direction: 1, role: role) } }
                }
                Divider()
                Button("Remove Form", role: .destructive) {
                    connectionToRemove = connection; showingRemoveConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundColor(.secondary)
            }
            .disabled(model.isWorking)
        }
        .padding(.vertical, 3)
    }

    private func sequenceDescription(position: Int) -> String {
        if role == .parent && position == 0 {
            return "Starts child intake and required document review."
        }
        return position == 0
            ? "First Form recipients complete."
            : "Available after the earlier Form is approved."
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
    @State private var formSearch = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(school: School, role: SchoolRole, existing: GoogleFormConnection?, displayOrder: Int, onSaved: @escaping () -> Void) {
        self.school = school; self.role = role; self.existing = existing; self.displayOrder = displayOrder; self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                if credential == nil {
                    Section("Connect Google") {
                        Text("Sign in with the director-owned Google account that can read these Forms and their responses. FireflyFM stores only an encrypted backend credential.")
                            .font(.caption).foregroundColor(.secondary)
                        Button("Connect Google Account", systemImage: "person.badge.key") {
                            Task { await connectGoogle() }
                        }
                        .disabled(isWorking)
                    }
                } else if selectedForm == nil {
                    Section("Choose a Form") {
                        Text("Search the Forms this Google account can access. You will place the selected Form in the recipient sequence next.")
                            .font(.caption).foregroundColor(.secondary)
                        if forms.isEmpty {
                            Text("No Google Forms were found in this account.").foregroundColor(.secondary)
                        } else {
                            ForEach(filteredForms) { form in
                                Button {
                                    Task { await choose(form) }
                                } label: {
                                    HStack {
                                        Text(form.title)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        Button("Use another Google account") {
                            credential = nil; forms = []; selectedForm = nil; formSearch = ""
                        }
                        .font(.caption)
                    }
                } else if let form = selectedForm {
                    Section {
                        Label(form.title, systemImage: "doc.text.fill")
                            .font(.headline)
                        Text(role == .parent
                             ? "FireflyFM recognizes the child-intake questions, creates the private review request, and marks the next onboarding step complete only after approval."
                             : "FireflyFM recognizes the submission-reference question and marks the next onboarding step complete after approval.")
                            .font(.caption).foregroundColor(.secondary)
                        Button("Choose a different Form") { selectedForm = nil }
                            .font(.caption)
                    }
                    Section("Automatic setup") {
                        Label("Standard questions are recognized automatically", systemImage: "checkmark.circle.fill")
                        Label("This becomes the next required onboarding step", systemImage: "arrow.right.circle.fill")
                        if role == .parent {
                            Text("Required labels: Child first name, Child last name, Child birthdate, Parent or guardian relationship, Parent email, and FireflyFM submission reference.")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("Required label: FireflyFM submission reference.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundColor(.red) } }
            }
            .navigationTitle(existing == nil ? "Add Form" : "Replace Form")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") { Task { await save() } }
                        .disabled(selectedForm == nil || isWorking)
                }
            }
            .searchable(text: $formSearch, prompt: "Search Google Forms")
        }
    }

    private var filteredForms: [GoogleAuthorizedForm] {
        let query = formSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return forms }
        return forms.filter { $0.title.localizedCaseInsensitiveContains(query) }
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
        } catch { errorMessage = AppErrorMessage.school("Could not read Form questions", error) }
    }

    @MainActor
    private func save() async {
        guard let credential, let form = selectedForm else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await SchoolWorkflowService.shared.connectGoogleForm(
                schoolId: school.id, role: role, credentialId: credential.credentialId, form: form,
                formKey: existing?.formKey ?? form.id, displayOrder: existing?.displayOrder ?? displayOrder
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
