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

    func load(schoolId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            connections = try await SchoolWorkflowService.shared.fetchParentGoogleFormConnections(schoolId: schoolId)
        } catch where AppErrorMessage.isCancellation(error) {} catch {
            errorMessage = AppErrorMessage.school("Could not load the parent form", error)
        }
    }

    func connect(schoolId: UUID, url: String, title: String?, accountEmail: String?) async {
        guard let formId = Self.formID(from: url) else {
            errorMessage = "Enter a Google Forms edit or response URL."
            return
        }
        isWorking = true
        errorMessage = nil
        notice = nil
        defer { isWorking = false }
        do {
            let saved = try await SchoolWorkflowService.shared.connectParentGoogleForm(
                schoolId: schoolId,
                formId: formId,
                formURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
                title: title,
                accountEmail: accountEmail
            )
            connections = connections.filter { $0.id != saved.id } + [saved]
            notice = "Form connected. Add the required upload questions in Google Forms, then use Sync Now to test responses."
        } catch { errorMessage = AppErrorMessage.school("Could not connect the parent form", error) }
    }

    func sync(schoolId: UUID) async {
        isWorking = true
        errorMessage = nil
        notice = nil
        defer { isWorking = false }
        do {
            try await SchoolWorkflowService.shared.requestParentGoogleFormSync(schoolId: schoolId)
            notice = "Sync requested. New responses will appear in the review queue when processing finishes."
            await load(schoolId: schoolId)
        } catch { errorMessage = AppErrorMessage.school("Could not start form sync", error) }
    }

    func disconnect(schoolId: UUID) async {
        isWorking = true
        errorMessage = nil
        do {
            try await SchoolWorkflowService.shared.disconnectParentGoogleForm(schoolId: schoolId)
            connections.removeAll()
            notice = "The form was removed from FireflyFM. The Google Drive form was not deleted."
        } catch { errorMessage = AppErrorMessage.school("Could not remove the parent form", error) }
        isWorking = false
    }

    var primaryConnection: GoogleFormConnection? {
        connections.first(where: { $0.formKey == nil || $0.formKey == "parent_intake" })
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
    @State private var model = GoogleFormOnboardingModel()
    @State private var showingConnect = false
    @State private var showingRemoveConfirmation = false

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
            .refreshable { await model.load(schoolId: school.id) }
        }
        .navigationTitle("Parent Form")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(schoolId: school.id) }
        .sheet(isPresented: $showingConnect) {
            GoogleFormConnectionSheet(school: school, existing: model.primaryConnection) {
                Task { await model.load(schoolId: school.id) }
            }
        }
        .confirmationDialog("Remove this form from FireflyFM?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove Connection", role: .destructive) { Task { await model.disconnect(schoolId: school.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Google Form and its responses will remain in the director's Google account.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(school.name).font(.caption.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
            Text("Parent onboarding form").font(.largeTitle.bold()).foregroundColor(AppConstants.Colors.primaryText)
            Text("Connect one Google Form for child intake, health information, emergency contacts, medicine, and required documents.")
                .font(.subheadline).foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Parent Intake", systemImage: "list.clipboard.fill").font(.headline)
                Spacer()
                Text(statusTitle(for: model.primaryConnection))
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(statusColor(for: model.primaryConnection).opacity(0.22))
                    .clipShape(Capsule())
            }
            if let connection = model.primaryConnection {
                Text(connection.formTitle ?? "Parent onboarding form").font(.title3.bold())
                Text("Child intake, health information, and required documents")
                    .font(.subheadline).foregroundColor(.secondary)
                if let email = connection.googleAccountEmail { Text(email).font(.caption).foregroundColor(.secondary) }
                if let synced = connection.lastSyncedAt { Text("Last synced \(synced.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundColor(.secondary) }
                HStack {
                    Button { Task { await model.sync(schoolId: school.id) } } label: { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.borderedProminent).tint(AppConstants.Colors.accessibleYellow)
                    Spacer()
                    Menu {
                        Button("Update Form") { showingConnect = true }
                        Button("Connection details") { }
                        Divider()
                        Button("Remove Form", role: .destructive) { showingRemoveConfirmation = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .accessibilityLabel("Form actions")
                    }
                }
                .disabled(model.isWorking)
            } else {
                Text("Connect the director-managed Google Form used for parent intake.")
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.65))
                Button("Connect Google Form", systemImage: "link") { showingConnect = true }
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
                            Text(connection.formTitle ?? "Additional form").font(.subheadline.bold())
                            Text(statusTitle(for: connection)).font(.caption).foregroundColor(statusColor(for: connection))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } label: {
                Text("Additional forms").font(.headline)
            }
            .padding().background(AppConstants.Colors.card).cornerRadius(10)
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
    let existing: GoogleFormConnection?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url: String
    @State private var title: String
    @State private var accountEmail: String
    @State private var errorMessage: String?

    init(school: School, existing: GoogleFormConnection?, onSaved: @escaping () -> Void) {
        self.school = school; self.existing = existing; self.onSaved = onSaved
        _url = State(initialValue: existing?.formURL ?? "")
        _title = State(initialValue: existing?.formTitle ?? "Parent onboarding form")
        _accountEmail = State(initialValue: existing?.googleAccountEmail ?? "")
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
                            await model.connect(schoolId: school.id, url: url, title: title, accountEmail: accountEmail)
                            if model.errorMessage == nil { onSaved(); dismiss() } else { errorMessage = model.errorMessage }
                        }
                    }
                }
            }
        }
    }
}
