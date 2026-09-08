import SwiftUI
import Observation

enum GoogleAccountConnectionPolicy {
    static func isVisible(canEditProfile: Bool, role: SchoolRole?, schoolId: UUID?) -> Bool {
        canEditProfile && role == .schoolDirector && schoolId != nil
    }

    static let disconnectExplanation = "FireflyFM will revoke this account’s Google access and pause its linked Forms. Google Forms and previously imported FireflyFM records will not be deleted. Reconnecting this account resumes those Forms."
}

struct GoogleAccountConnectionClient {
    var list: (UUID) async throws -> [GoogleAccountConnectionSummary]
    var select: (UUID, UUID) async throws -> Void
    var disconnect: (UUID, UUID) async throws -> Int
    var startOAuth: (UUID, String?) async throws -> GoogleFormsOAuthStart
    var authorize: (URL, String) async throws -> URL
    var completeOAuth: (UUID, URL) async throws -> GoogleFormsOAuthCompletion

    static let live = GoogleAccountConnectionClient(
        list: { try await SchoolWorkflowService.shared.fetchGoogleAccountConnections(schoolId: $0) },
        select: { try await SchoolWorkflowService.shared.selectGoogleAccount(schoolId: $0, credentialId: $1) },
        disconnect: { try await SchoolWorkflowService.shared.disconnectGoogleAccount(schoolId: $0, credentialId: $1) },
        startOAuth: { try await SchoolWorkflowService.shared.startGoogleFormsOAuth(schoolId: $0, accountEmail: $1) },
        authorize: { try await GoogleFormsWebAuthenticator.shared.authorize(url: $0, callbackScheme: $1) },
        completeOAuth: { try await SchoolWorkflowService.shared.completeGoogleFormsOAuth(schoolId: $0, callbackURL: $1) }
    )
}

@MainActor
@Observable
final class GoogleAccountConnectionModel {
    private let client: GoogleAccountConnectionClient
    private(set) var accounts: [GoogleAccountConnectionSummary] = []
    private(set) var isLoading = false
    private(set) var workingCredentialId: UUID?
    private(set) var isConnecting = false
    private(set) var errorMessage: String?
    private(set) var notice: String?

    init(client: GoogleAccountConnectionClient = .live) {
        self.client = client
    }

    var selectedAccount: GoogleAccountConnectionSummary? {
        accounts.first(where: { $0.isSelected && $0.isConnected })
            ?? accounts.first(where: \GoogleAccountConnectionSummary.isConnected)
    }

    func load(schoolId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            accounts = try await client.list(schoolId)
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not load Google connections", error)
        }
    }

    func select(_ account: GoogleAccountConnectionSummary, schoolId: UUID) async {
        workingCredentialId = account.id
        errorMessage = nil
        notice = nil
        defer { workingCredentialId = nil }
        do {
            try await client.select(schoolId, account.id)
            await load(schoolId: schoolId)
            notice = "New Forms will use \(account.accountEmail). Existing Forms keep their current account."
        } catch {
            errorMessage = AppErrorMessage.school("Could not switch Google accounts", error)
        }
    }

    func connect(schoolId: UUID, accountEmail: String? = nil) async {
        isConnecting = true
        errorMessage = nil
        notice = nil
        defer { isConnecting = false }
        do {
            let start = try await client.startOAuth(schoolId, accountEmail)
            guard let url = URL(string: start.authorizationURL) else {
                throw SchoolWorkflowError.invalidInput("Google returned an invalid authorization link.")
            }
            let callback = try await client.authorize(url, start.callbackScheme)
            let completed = try await client.completeOAuth(schoolId, callback)
            await load(schoolId: schoolId)
            notice = "Connected \(completed.accountEmail). New Forms will use this account."
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not connect Google", error)
        }
    }

    func disconnect(_ account: GoogleAccountConnectionSummary, schoolId: UUID) async {
        workingCredentialId = account.id
        errorMessage = nil
        notice = nil
        defer { workingCredentialId = nil }
        do {
            let pausedCount = try await client.disconnect(schoolId, account.id)
            await load(schoolId: schoolId)
            notice = pausedCount == 1
                ? "Google was disconnected and 1 linked Form was paused."
                : "Google was disconnected and \(pausedCount) linked Forms were paused."
        } catch {
            errorMessage = AppErrorMessage.school("Could not disconnect Google", error)
        }
    }
}

struct GoogleAccountConnectionProfileLink: View {
    let school: School
    @State private var model = GoogleAccountConnectionModel()

    var body: some View {
        NavigationLink {
            GoogleAccountConnectionView(school: school)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Google Connection")
                        .font(.subheadline.bold())
                    if model.isLoading {
                        Text("Checking connection…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let account = model.selectedAccount {
                        Text("\(account.accountEmail) · \(linkedFormsText(account.linkedFormCount))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Connect or manage Google accounts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .foregroundColor(AppConstants.Colors.primaryText)
            .padding(14)
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
        }
        .task(id: school.id) { await model.load(schoolId: school.id) }
    }

    private func linkedFormsText(_ count: Int) -> String {
        count == 1 ? "1 linked Form" : "\(count) linked Forms"
    }
}

struct GoogleAccountConnectionView: View {
    let school: School
    @State private var model = GoogleAccountConnectionModel()
    @State private var accountToDisconnect: GoogleAccountConnectionSummary?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    if model.isLoading && model.accounts.isEmpty {
                        ProgressView("Loading Google connections")
                            .frame(maxWidth: .infinity)
                    } else {
                        accountList
                    }
                    Button {
                        Task { await model.connect(schoolId: school.id) }
                    } label: {
                        Label("Connect another Google account", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppConstants.Colors.accessibleYellow)
                    .disabled(model.isConnecting || model.workingCredentialId != nil)

                    if let notice = model.notice { message(notice, color: .green) }
                    if let error = model.errorMessage { message(error, color: .red) }
                }
                .padding()
            }
            .refreshable { await model.load(schoolId: school.id) }
        }
        .navigationTitle("Google Connection")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: school.id) { await model.load(schoolId: school.id) }
        .confirmationDialog(
            "Disconnect \(accountToDisconnect?.accountEmail ?? "Google")?",
            isPresented: disconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect Google", role: .destructive) {
                guard let account = accountToDisconnect else { return }
                Task { await model.disconnect(account, schoolId: school.id) }
            }
            Button("Cancel", role: .cancel) { accountToDisconnect = nil }
        } message: {
            Text(GoogleAccountConnectionPolicy.disconnectExplanation)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(school.name)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text("Choose the Google account used when adding new onboarding Forms. Existing Forms stay with the account that connected them.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
        }
    }

    @ViewBuilder
    private var accountList: some View {
        if model.accounts.isEmpty {
            ContentUnavailableView(
                "Google is not connected",
                systemImage: "person.crop.circle.badge.plus",
                description: Text("Connect a director-owned account that can access the school’s onboarding Forms.")
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.accounts.enumerated()), id: \GoogleAccountConnectionSummary.id) { index, account in
                    if index > 0 { Divider() }
                    accountRow(account)
                }
            }
            .background(AppConstants.Colors.card)
            .cornerRadius(10)
        }
    }

    private func accountRow(_ account: GoogleAccountConnectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.accountEmail)
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text(account.linkedFormCount == 1 ? "1 linked Form" : "\(account.linkedFormCount) linked Forms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusBadge(account)
            }

            HStack {
                if account.isConnected && !account.isSelected {
                    Button("Use for new Forms") {
                        Task { await model.select(account, schoolId: school.id) }
                    }
                    .buttonStyle(.bordered)
                }
                if account.needsReconnect {
                    Button("Reconnect") {
                        Task { await model.connect(schoolId: school.id, accountEmail: account.accountEmail) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppConstants.Colors.accessibleYellow)
                }
                Spacer()
                if account.isConnected {
                    Button("Disconnect", role: .destructive) { accountToDisconnect = account }
                        .buttonStyle(.borderless)
                }
            }
            .font(.caption.bold())
            .disabled(model.isConnecting || model.workingCredentialId != nil)
        }
        .padding()
    }

    private func statusBadge(_ account: GoogleAccountConnectionSummary) -> some View {
        Text(account.isSelected && account.isConnected ? "Selected" : account.isConnected ? "Connected" : "Disconnected")
            .font(.caption2.bold())
            .foregroundColor(account.isConnected ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((account.isConnected ? Color.green : Color.orange).opacity(0.14))
            .clipShape(Capsule())
    }

    private var disconnectConfirmation: Binding<Bool> {
        Binding(
            get: { accountToDisconnect != nil },
            set: { if !$0 { accountToDisconnect = nil } }
        )
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(8)
    }
}
