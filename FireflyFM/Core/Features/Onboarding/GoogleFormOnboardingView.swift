import SwiftUI
import Observation

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

    func connect(schoolId: UUID, role: SchoolRole, url: String, title: String?, accountEmail: String?, isRequired: Bool, displayOrder: Int) async {
        guard let formId = Self.formID(from: url) else {
            errorMessage = "Enter a Google Forms edit or response URL."
            return
        }
        isWorking = true
        errorMessage = nil
        notice = nil
        defer { isWorking = false }
        do {
            let saved = try await SchoolWorkflowService.shared.connectGoogleForm(
                schoolId: schoolId, role: role, formKey: formId, formId: formId,
                formURL: url.trimmingCharacters(in: .whitespacesAndNewlines), title: title,
                accountEmail: accountEmail, isRequired: isRequired, displayOrder: displayOrder
            )
            connections = (connections.filter { $0.id != saved.id } + [saved])
                .sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }
            notice = "Form connected. Add the required upload questions in Google Forms, then use Sync Now to test responses."
        } catch { errorMessage = AppErrorMessage.school("Could not connect the form", error) }
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
    @State private var url: String
    @State private var title: String
    @State private var accountEmail: String
    @State private var isRequired: Bool
    @State private var errorMessage: String?

    init(school: School, role: SchoolRole, existing: GoogleFormConnection?, displayOrder: Int, onSaved: @escaping () -> Void) {
        self.school = school; self.role = role; self.existing = existing; self.displayOrder = displayOrder; self.onSaved = onSaved
        _url = State(initialValue: existing?.formURL ?? "")
        _title = State(initialValue: existing?.formTitle ?? (role == .parent ? "Parent onboarding form" : "Teacher onboarding form"))
        _accountEmail = State(initialValue: existing?.googleAccountEmail ?? "")
        _isRequired = State(initialValue: existing?.isRequired ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Google Form") {
                    TextField("Google Forms URL", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Form name", text: $title)
                    TextField("Google account email", text: $accountEmail)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Required for access", isOn: $isRequired)
                }
                Section {
                    Text("The director must own or have edit access to this form. Google OAuth credential storage and live response sync require the deployment’s Google Cloud configuration.")
                        .font(.caption).foregroundColor(.secondary)
                    if let errorMessage { Text(errorMessage).foregroundColor(.red) }
                }
            }
            .navigationTitle(existing == nil ? "Connect Form" : "Update Form")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard GoogleFormOnboardingModel.formID(from: url) != nil else { errorMessage = "Enter a valid Google Forms URL."; return }
                        Task {
                            let model = GoogleFormOnboardingModel()
                            await model.connect(schoolId: school.id, role: role, url: url, title: title, accountEmail: accountEmail, isRequired: isRequired, displayOrder: existing?.displayOrder ?? displayOrder)
                            if model.errorMessage == nil { onSaved(); dismiss() } else { errorMessage = model.errorMessage }
                        }
                    }
                }
            }
        }
    }
}
