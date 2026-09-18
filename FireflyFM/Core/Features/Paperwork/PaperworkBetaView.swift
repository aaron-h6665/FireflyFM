import SwiftUI
import Supabase

struct PaperworkWorkspaceView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    var body: some View {
        if AppConfiguration.workspaceBetaEnabled { PaperworkBetaView().id("\(appSession.profile?.id.uuidString ?? ""):\(appSession.activeMembershipId?.uuidString ?? "")") }
        else { LegacyPaperworkWorkspaceView() }
    }
}

struct WorkspacePersonLabel: Decodable {
    let user_id: UUID
    let display_name: String
    var school_id: UUID?
}

struct PaperworkBetaView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var perspective: WorkspacePerspective = .manage
    @State private var bucket: WorkspaceBucket = .attention
    private enum Section: String, CaseIterable { case active, history, unmatched, names, schools, access }
    private enum Payload {
        case items([PaperworkItem]), unmatched([GoogleFormImport]), names([WorkspacePersonLabel]), schools([School]), access(String)
    }
    @State private var loader = WorkspaceSectionLoader<Section, Payload>()
    private var scope: WorkspaceLoadScope {
        WorkspaceLoadScope(userId: appSession.profile?.id, membershipId: appSession.activeMembershipId, schoolId: schoolId)
    }
    private func value(_ section: Section) -> Payload? { loader.scope == scope ? loader.values[section] : nil }
    private var items: [PaperworkItem] {
        var seen = Set<String>()
        return [Section.active, .history].flatMap { section -> [PaperworkItem] in
            if case .items(let items) = value(section) { return items }; return []
        }.filter { seen.insert($0.workspaceIdentity).inserted }
    }
    private var unmatched: [GoogleFormImport] { if case .unmatched(let rows) = value(.unmatched) { return rows }; return [] }
    private var names: [UUID: String] {
        if case .names(let rows) = value(.names) { return Dictionary(rows.map { ($0.user_id, $0.display_name) }, uniquingKeysWith: { first, _ in first }) }; return [:]
    }
    private var schools: [School] { if case .schools(let rows) = value(.schools) { return rows }; return [] }
    private var loading: Bool { loader.scope != scope || !loader.loading.isEmpty }
    private var currentSection: Section { bucket == .history ? .history : .active }
    @State private var selectedSchool: UUID?
    @State private var query = ""
    @State private var composer = false
    private var managing: Bool { appSession.workspaceManaging(perspective) }
    private var schoolId: UUID? { selectedSchool ?? appSession.activeSchool?.id }
    private var school: School? { schools.first { $0.id == schoolId } ?? (appSession.activeSchool?.id == schoolId ? appSession.activeSchool : nil) }
    private var ownAttention: Int {
        items.filter { $0.recipientId == appSession.profile?.id && WorkspaceBucket.paperwork(status: $0.status, managing: false) == .attention }.count
    }
    private var roleItems: [PaperworkItem] {
        items.filter { managing ? $0.recipientId != appSession.profile?.id : $0.recipientId == appSession.profile?.id }
    }
    private var bucketCounts: [WorkspaceBucket: Int] {
        var counts = Dictionary(grouping: roleItems) { WorkspaceBucket.paperwork(status: $0.status, managing: managing) }
            .mapValues(\.count)
        if managing {
            let unmatchedOnly = unmatched.filter { response in
                !roleItems.contains { $0.googleFormImportId == response.id }
            }.count
            counts[.attention, default: 0] += unmatchedOnly
        }
        return counts
    }
    private var filtered: [PaperworkItem] {
        guard case .items(let sectionItems) = value(currentSection) else { return [] }
        return sectionItems.filter {
            (managing ? $0.recipientId != appSession.profile?.id : $0.recipientId == appSession.profile?.id)
            && WorkspaceBucket.paperwork(status: $0.status, managing: managing) == bucket
            && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || (names[$0.recipientId] ?? "").localizedCaseInsensitiveContains(query))
        }
    }
    private var groups: [WorkspaceGroup<PaperworkItem>] {
        Dictionary(grouping: filtered) { item in
            "\(item.schoolId):\(item.sourceKind.rawValue):\(item.nativeRequestId ?? item.googleFormConnectionId ?? item.itemId)"
        }.map { WorkspaceGroup(id: $0.key, items: $0.value) }.sorted { ($0.items.first?.title ?? "") < ($1.items.first?.title ?? "") }
    }
    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if appSession.role == .schoolDirector && appSession.workspaceCanManage {
                        WorkspacePerspectivePicker(selection: $perspective, attentionCount: ownAttention)
                    }
                    if appSession.role == .hqDirector {
                        Picker("School", selection: Binding(get: { schoolId }, set: { selectedSchool = $0 })) {
                            ForEach(schools) { Text($0.name).tag(Optional($0.id)) }
                        }.pickerStyle(.menu)
                    }
                    if appSession.activeContext?.membership.accessState == "onboarding" {
                        let completed = items.filter { ["approved", "accepted", "waived", "excused"].contains($0.status) }.count
                        ProgressView("Setup · \(completed) of \(items.count) complete", value: Double(completed), total: Double(max(1, items.count)))
                    }
                    WorkspaceBucketPicker(selection: $bucket, managing: managing, counts: bucketCounts)
                    if loading && items.isEmpty { ProgressView("Loading paperwork…") }
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
                    if value(currentSection) != nil && loader.errors[currentSection] == nil && !loader.loading.contains(currentSection) && filtered.isEmpty {
                        FireflyEmptyState(title: "No paperwork here", message: "Assigned items appear here when they need attention.", systemImage: "doc.text")
                    }
                    if managing && bucket == .attention && !unmatched.isEmpty, let school {
                        Text("Needs matching").font(.headline)
                        WorkspaceList {
                            ForEach(Array(unmatched.enumerated()), id: \.element.id) { index, response in
                                NavigationLink { GoogleFormImportDetailView(school: school, item: response, onChanged: { Task { await load() } }) }
                                label: { WorkspaceRow(title: response.respondentEmail ?? "Unmatched response", subtitle: response.status.replacingOccurrences(of: "_", with: " ").capitalized) }
                                .buttonStyle(.plain)
                                if index < unmatched.count - 1 { Divider().padding(.leading, 44) }
                            }
                        }
                    }
                    WorkspaceList {
                        if managing {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { index, entry in
                                let group = entry.items
                                if let first = group.first {
                                    NavigationLink {
                                        PaperworkRecipientList(items: group, names: names, school: school, onChanged: { Task { await load() } })
                                    } label: {
                                        WorkspaceRow(
                                            title: first.title,
                                            subtitle: "\(group.count) recipient\(group.count == 1 ? "" : "s") · \(bucket.title(managing: true))"
                                        )
                                    }.buttonStyle(.plain)
                                    if index < groups.count - 1 { Divider().padding(.leading, 44) }
                                }
                            }
                        } else {
                            ForEach(Array(filtered.enumerated()), id: \.element.workspaceIdentity) { index, item in
                                NavigationLink {
                                    PaperworkBetaDestination(item: item, school: school, reviewing: false, onChanged: { Task { await load() } })
                                } label: { WorkspaceRow(title: item.title, subtitle: item.status.replacingOccurrences(of: "_", with: " ").capitalized) }
                                .buttonStyle(.plain)
                                if index < filtered.count - 1 { Divider().padding(.leading, 44) }
                            }
                        }
                    }
                }.padding()
            }
        }
        .navigationTitle("Paperwork")
        .searchable(text: $query, prompt: managing ? "Search forms or recipients" : "Search paperwork")
        .toolbar { if managing { Button { composer = true } label: { Label("New paperwork", systemImage: "plus") } } }
        .sheet(isPresented: $composer) {
            if let schoolId { PaperworkComposerView(schoolId: schoolId) { Task { await load() } } }
        }
        .task(id: scope) { await load() }
        .refreshable { await load() }
        .onChange(of: scope) { _, scope in loader.reset(to: scope) }
    }
    private func load() async {
        let requestedScope = scope
        loader.reset(to: requestedScope)
        async let active: Void = loadSection(.active, scope: requestedScope)
        async let history: Void = loadSection(.history, scope: requestedScope)
        async let names: Void = loadSection(.names, scope: requestedScope)
        async let unmatched: Void = loadSection(.unmatched, scope: requestedScope)
        async let schools: Void = loadSection(.schools, scope: requestedScope)
        async let access: Void = loadSection(.access, scope: requestedScope)
        _ = await (active, history, names, unmatched, schools, access)
    }
    private func loadSection(_ section: Section, scope requestedScope: WorkspaceLoadScope) async {
        guard requestedScope == scope else { return }
        let isHQ = appSession.role == .hqDirector
        let canManage = appSession.workspaceCanManage
        let onboarding = appSession.activeContext?.membership.accessState == "onboarding"
        await loader.load(section, scope: requestedScope, failureMessage: "Could not load paperwork \(section.rawValue)") {
            struct Params: Encodable { let input_school_id: UUID; let input_archived: Bool }
            struct Labels: Encodable { let input_school_id: UUID }
            if section == .schools { return .schools(isHQ ? try await SchoolService.shared.fetchSchoolsForHQ() : []) }
            guard let schoolId = requestedScope.schoolId else { throw URLError(.badURL) }
            switch section {
            case .active, .history:
                let rows: [PaperworkItem] = try await AppConstants.supabase.rpc("fetch_my_paperwork_items_v2", params: Params(input_school_id: schoolId, input_archived: section == .history)).execute().value
                return .items(rows)
            case .names:
                let rows: [WorkspacePersonLabel] = try await AppConstants.supabase.rpc("fetch_workspace_recipient_labels", params: Labels(input_school_id: schoolId)).execute().value
                return .names(rows)
            case .unmatched:
                let rows: [GoogleFormImport] = canManage ? try await AppConstants.supabase.rpc("fetch_unmatched_paperwork_responses", params: Labels(input_school_id: schoolId)).execute().value : []
                return .unmatched(rows)
            case .access:
                return .access(onboarding ? try await SchoolWorkflowService.shared.refreshMyOnboardingAccess(schoolId: schoolId) : "unchanged")
            case .schools: return .schools([])
            }
        }
        guard requestedScope == scope, !Task.isCancelled else { return }
        if section == .schools, requestedScope.schoolId == nil { selectedSchool = schools.first?.id }
        if section == .access, case .access("full") = value(.access), onboarding {
            await appSession.refresh(selecting: requestedScope.membershipId)
        }
    }

}

extension PaperworkItem {
    var workspaceIdentity: String { "\(schoolId):\(sourceKind.rawValue):\(itemId):\(recipientId):\(childId?.uuidString ?? "member")" }
}

struct PaperworkRecipientList: View {
    let items: [PaperworkItem]
    let names: [UUID: String]
    let school: School?
    let onChanged: () -> Void
    var body: some View {
        FireflyScreen {
            ScrollView {
                WorkspaceList {
                    ForEach(Array(items.enumerated()), id: \.element.workspaceIdentity) { index, item in
                        NavigationLink {
                            PaperworkBetaDestination(item: item, school: school, reviewing: true, onChanged: onChanged)
                        } label: { WorkspaceRow(title: names[item.recipientId] ?? "Recipient", subtitle: item.status.replacingOccurrences(of: "_", with: " ").capitalized) }
                        .buttonStyle(.plain)
                        if index < items.count - 1 { Divider().padding(.leading, 44) }
                    }
                }.padding()
            }
        }.navigationTitle(items.first?.title ?? "Recipients")
    }
}

struct PaperworkBetaDestination: View {
    @EnvironmentObject private var appSession: AppSessionManager
    let item: PaperworkItem
    let school: School?
    let reviewing: Bool
    let onChanged: () -> Void
    @State private var response: GoogleFormImport?
    @State private var attachments: [GoogleFormImportAttachment] = []
    @State private var error: String?
    @State private var formURL: URL?
    @State private var showingForm = false
    @State private var working = false
    var body: some View {
        Group {
            if let request = item.nativeRequestId {
                LazyPaperworkRequestDetailView(requestId: request, canReview: reviewing, recipientId: item.recipientId, onChanged: onChanged)
            } else if let response, let school {
                if reviewing { GoogleFormImportDetailView(school: school, item: response, onChanged: onChanged) }
                else {
                    Form {
                        Section("Your answers") { ForEach(response.displayedAnswers) { LabeledContent($0.title, value: $0.value) } }
                        if !attachments.isEmpty {
                            Section("Files") { ForEach(attachments) { PaperworkFileButton(name: $0.fileName, path: $0.privateFilePath) } }
                        }
                        CorrectionChecklist(googleImportId: response.id, submissionId: nil)
                        if let note = response.reviewNote { Section("Feedback") { Text(note) } }
                        if item.status == "changes_requested" { Section { openFormButton } }
                        if let error { Section { FireflyInlineError(message: error) } }
                        Section { Button("Check response") { Task { await checkResponse() } } }
                    }
                }
            } else {
                Form {
                    Section { Text(item.title); Text(item.status.replacingOccurrences(of: "_", with: " ").capitalized) }
                    if !reviewing && item.googleFormConnectionId != nil { Section { openFormButton } }
                    if let error { Section { FireflyInlineError(message: error) } }
                    if !reviewing { Section { Button("Check response") { Task { await checkResponse() } } } }
                }
            }
        }
        .navigationTitle(item.title)
        .toolbar {
            if let requirement = item.onboardingRequirementInstanceId, item.sourceKind == .googleForm {
                NavigationLink { PaperworkResponseHistory(requirementId: requirement) } label: { Label("History", systemImage: "clock.arrow.circlepath") }
            }
        }
        .sheet(isPresented: $showingForm, onDismiss: { Task { await checkResponse() } }) {
            if let formURL { FireflySafariView(url: formURL).ignoresSafeArea() }
        }
        .task { await loadResponse() }
    }
    private var openFormButton: some View {
        Button(working ? "Opening…" : (item.status == "changes_requested" ? "Update submission" : "Open Google Form")) {
            Task {
                working = true
                defer { working = false }
                do {
                    guard let id = item.googleFormConnectionId else { return }
                    let launch = try await SchoolWorkflowService.shared.beginGoogleFormSubmission(connectionId: id)
                    guard let url = URL(string: launch.launchURL) else { return }
                    formURL = url; showingForm = true
                } catch { self.error = AppErrorMessage.school("Could not open form", error) }
            }
        }.disabled(working)
    }
    private func loadResponse() async {
        guard let id = item.googleFormImportId else { return }
        do {
            let rows: [GoogleFormImport] = try await AppConstants.supabase.from("google_form_imports").select().eq("id", value: id).execute().value
            response = rows.first
            attachments = try await SchoolWorkflowService.shared.fetchGoogleFormImportAttachments(importId: id)
        } catch { self.error = AppErrorMessage.school("Could not load response", error) }
    }
    private func checkResponse() async {
        do {
            try await SchoolWorkflowService.shared.requestGoogleFormSync(schoolId: item.schoolId, role: appSession.role ?? .parent, connectionId: item.googleFormConnectionId)
            onChanged()
        } catch { self.error = AppErrorMessage.school("Could not check response", error) }
    }
}
