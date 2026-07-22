import SwiftUI

struct ChildrenView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var schools: [School] = []
    @State private var children: [Child] = []
    @State private var showingConnection = false
    @State private var showingConnectionReview = false
    @State private var editingChild: Child?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(descriptionText)
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.secondaryText)

                    if appSession.role == .parent, isLoading == false {
                        parentStatusCard
                    }
                    if appSession.role?.canManageSchool == true, missingBirthdates.isEmpty == false {
                        remediationCard
                    }

                    if isLoading {
                        ProgressView().tint(AppConstants.Colors.accessibleYellow)
                    } else if children.isEmpty {
                        emptyPanel
                    } else if appSession.role == .hqDirector {
                        ForEach(schoolGroups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Label(group.schoolName, systemImage: "building.2.fill")
                                    .font(.title3.bold()).foregroundColor(AppConstants.Colors.primaryText)
                                childGrid(group.children)
                            }
                        }
                    } else {
                        childGrid(children)
                    }

                    if let errorMessage { Text(errorMessage).font(.caption).foregroundColor(.red) }
                }
                .padding()
            }
            .refreshable { await load() }
        }
        .navigationTitle("Children")
        .toolbar {
            if appSession.role == .parent {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingConnection = true } label: {
                        Label("Connect a Child", systemImage: "link.badge.plus")
                    }
                    .tint(AppConstants.Colors.accessibleYellow)
                }
            }
            if appSession.role == .schoolDirector {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingConnectionReview = true } label: {
                        Label("Connection Requests", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .tint(AppConstants.Colors.accessibleYellow)
                }
            }
        }
        .sheet(isPresented: $showingConnection) {
            if let school = appSession.activeSchool {
                ChildConnectionView(school: school) { Task { await load() } }
            }
        }
        .sheet(isPresented: $showingConnectionReview) {
            if let school = appSession.activeSchool {
                ChildConnectionReviewView(school: school) { Task { await load() } }
            }
        }
        .sheet(item: $editingChild) { child in
            DirectorChildIdentityEditor(child: child) { Task { await load() } }
        }
        .task(id: appSession.activeMembershipId) { await load() }
    }

    private var parentStatusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: children.isEmpty ? "link.badge.plus" : "checkmark.seal.fill")
                .font(.title2).foregroundColor(AppConstants.Colors.accessibleYellow)
            VStack(alignment: .leading, spacing: 3) {
                Text(children.isEmpty ? "Child connection needed" : "Child identity approved")
                    .font(.headline).foregroundColor(AppConstants.Colors.primaryText)
                Text(children.isEmpty
                     ? "Connect a child to continue onboarding. A request does not reveal or unlock a child until a director approves it."
                     : "Open Work to complete any child forms or intake tasks still required by your school.")
                    .font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
            }
            Spacer()
        }
        .padding().background(AppConstants.Colors.card).cornerRadius(10)
    }

    private var remediationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Birthdates need attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundColor(.orange)
            Text("Birthdate is required for all new records. Complete these legacy identities before using date-sensitive forms.")
                .font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
            ForEach(missingBirthdates) { child in
                Button { editingChild = child } label: {
                    HStack { Text(child.fullName); Spacer(); Text("Add birthdate").font(.caption.bold()) }
                }
                .buttonStyle(.bordered).tint(AppConstants.Colors.accessibleYellow)
            }
        }
        .padding().background(AppConstants.Colors.card).cornerRadius(10)
    }

    private func childGrid(_ values: [Child]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
            ForEach(values) { child in
                NavigationLink { ChildProfileView(child: child) } label: {
                    ChildRosterProfileCard(child: child)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if appSession.role?.canManageSchool == true {
                        Button { editingChild = child } label: { Label("Edit identity", systemImage: "pencil") }
                    }
                }
            }
        }
    }

    private var emptyPanel: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.2.and.child.holdinghands").font(.system(size: 44))
            Text(appSession.role == .parent ? "No approved child connection" : "No active child records")
                .font(.headline)
            Text(appSession.role == .parent
                 ? "Use Connect a Child. School staff will privately match and approve the request."
                 : "Approved school child records will appear here.")
                .font(.subheadline).multilineTextAlignment(.center)
        }
        .foregroundColor(AppConstants.Colors.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 240).padding().background(AppConstants.Colors.card).cornerRadius(10)
    }

    private var missingBirthdates: [Child] { children.filter { $0.birthdate == nil } }
    private var descriptionText: String {
        switch appSession.role {
        case .parent: "Approved child profiles and intake status. Attendance and daily care appear in each child’s timeline."
        case .teacher: "School-wide roster and child profiles. Use Attendance and Care Today for daily operations."
        case .schoolDirector: "Manage the school roster, approve guardian connections, and remediate incomplete identities."
        case .hqDirector: "Cross-school roster and profile oversight."
        case nil: "Child profiles."
        }
    }

    private var schoolGroups: [ChildSchoolGroup] {
        let names = Dictionary(uniqueKeysWithValues: schools.map { ($0.id, $0.name) })
        return Dictionary(grouping: children, by: \.schoolId).map { key, value in
            ChildSchoolGroup(schoolId: key, schoolName: names[key] ?? "School", children: value)
        }.sorted { $0.schoolName < $1.schoolName }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            if appSession.role == .hqDirector {
                async let loadedSchools = SchoolService.shared.fetchSchoolsForHQ()
                async let loadedChildren = SchoolWorkflowService.shared.fetchAllChildrenForHQ()
                schools = try await loadedSchools
                children = try await loadedChildren
            } else if let schoolId = appSession.activeSchool?.id {
                children = try await SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)
            } else { children = [] }
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = AppErrorMessage.school("Could not load children", error)
        }
    }
}

private struct ChildSchoolGroup: Identifiable {
    let schoolId: UUID
    let schoolName: String
    let children: [Child]
    var id: UUID { schoolId }
}

private struct ChildRosterProfileCard: View {
    let child: Child
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(AppConstants.Colors.background.opacity(0.55)).frame(width: 52, height: 52)
                .overlay(Text(initials).font(.headline.bold()).foregroundColor(AppConstants.Colors.accessibleYellow))
            VStack(alignment: .leading, spacing: 5) {
                Text(child.fullName).font(.headline).foregroundColor(AppConstants.Colors.primaryText)
                if let birthdate = child.birthdate {
                    Text("Born \(birthdate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
                } else {
                    Label("Birthdate required", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.orange)
                }
                Text("Open profile").font(.caption2.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(AppConstants.Colors.secondaryText)
        }
        .padding().frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(AppConstants.Colors.card).cornerRadius(10)
    }
    private var initials: String { String(child.firstName.prefix(1) + child.lastName.prefix(1)).uppercased() }
}

struct ChildConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    let school: School
    var onChanged: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
    @State private var relationship = "Parent"
    @State private var requests: [ChildConnectionRequest] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("How connections work") {
                    Text("If the school emailed you a child-specific invite, open that secure link while signed in with the invited email. Otherwise submit the legal identity below for private director review.")
                    Text("A pending request grants no profile access and does not confirm whether a matching child exists.")
                        .font(.caption).foregroundColor(.secondary)
                }
                if requests.isEmpty == false {
                    Section("Requests") {
                        ForEach(requests) { request in
                            HStack {
                                VStack(alignment: .leading) { Text(request.legalName); Text(request.status.rawValue.capitalized).font(.caption) }
                                Spacer()
                                Image(systemName: request.status == .approved ? "checkmark.seal.fill" : "clock.fill")
                            }
                        }
                    }
                }
                Section("Legal identity") {
                    TextField("Legal first name", text: $firstName)
                    TextField("Legal last name", text: $lastName)
                    DatePicker("Birthdate", selection: $birthdate, in: ...Date(), displayedComponents: .date)
                    TextField("Relationship", text: $relationship)
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("Connect a Child")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Submitting…" : "Submit") { submit() }
                        .disabled(isSaving || firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { await loadRequests() }
        }
    }

    private func submit() {
        isSaving = true; errorMessage = nil
        Task {
            do {
                _ = try await SchoolOperationsService.shared.submitConnectionRequest(
                    schoolId: school.id, legalFirstName: firstName, legalLastName: lastName,
                    birthdate: birthdate, relationship: relationship
                )
                await MainActor.run { firstName = ""; lastName = ""; isSaving = false; onChanged() }
                await loadRequests()
            } catch {
                await MainActor.run { isSaving = false; errorMessage = AppErrorMessage.school("Could not submit connection request", error) }
            }
        }
    }

    @MainActor private func loadRequests() async {
        do { requests = try await SchoolOperationsService.shared.fetchConnectionRequests(schoolId: school.id) }
        catch where AppErrorMessage.isCancellation(error) { return }
        catch { errorMessage = AppErrorMessage.school("Could not load requests", error) }
    }
}

struct ChildConnectionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let school: School
    var onChanged: () -> Void
    @State private var requests: [ChildConnectionRequest] = []
    @State private var children: [Child] = []
    @State private var selectedRequest: ChildConnectionRequest?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading { ProgressView() }
                if requests.isEmpty && !isLoading { Text("No pending connection requests.") }
                ForEach(requests) { request in
                    Button { selectedRequest = request } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.legalName).font(.headline)
                            Text("\(request.birthdate.formatted(date: .abbreviated, time: .omitted)) · \(request.relationship)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("Connection Requests")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $selectedRequest) { request in
                ConnectionDecisionView(request: request, children: children) { Task { await load() } }
            }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        do {
            async let loadedRequests = SchoolOperationsService.shared.fetchConnectionRequests(schoolId: school.id, status: .pending)
            async let loadedChildren = SchoolWorkflowService.shared.fetchChildren(schoolId: school.id)
            requests = try await loadedRequests; children = try await loadedChildren
            isLoading = false; onChanged()
        } catch where AppErrorMessage.isCancellation(error) { isLoading = false }
        catch { isLoading = false; errorMessage = AppErrorMessage.school("Could not load connection requests", error) }
    }
}

private struct ConnectionDecisionView: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChildConnectionRequest
    let children: [Child]
    var onChanged: () -> Void
    @State private var selectedChildId: UUID?
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Private match") {
                    LabeledContent("Requested name", value: request.legalName)
                    LabeledContent("Birthdate", value: request.birthdate.formatted(date: .long, time: .omitted))
                    LabeledContent("Relationship", value: request.relationship)
                }
                Section("Approve as") {
                    Picker("Child record", selection: $selectedChildId) {
                        Text("Create a new child record").tag(Optional<UUID>.none)
                        ForEach(children) { child in
                            Text("\(child.fullName) · \(child.birthdate?.formatted(date: .numeric, time: .omitted) ?? "Birthdate missing")")
                                .tag(Optional(child.id))
                        }
                    }
                    Text("Only select an existing record after privately verifying the identity. The parent cannot see possible matches.")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("Review note", text: $note, axis: .vertical)
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("Review Connection")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Reject", role: .destructive) { decide(approved: false) }
                    Spacer()
                    Button("Approve") { decide(approved: true) }.buttonStyle(.borderedProminent)
                }
                .padding().background(.bar)
            }
        }
    }

    private func decide(approved: Bool) {
        isSaving = true
        Task {
            do {
                _ = try await SchoolOperationsService.shared.reviewConnectionRequest(
                    requestId: request.id, approved: approved,
                    matchedChildId: approved ? selectedChildId : nil, note: note
                )
                await MainActor.run { isSaving = false; onChanged(); dismiss() }
            } catch {
                await MainActor.run { isSaving = false; errorMessage = AppErrorMessage.school("Could not review connection", error) }
            }
        }
    }
}

private struct DirectorChildIdentityEditor: View {
    @Environment(\.dismiss) private var dismiss
    let child: Child
    var onSaved: () -> Void
    @State private var firstName: String
    @State private var lastName: String
    @State private var birthdate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(child: Child, onSaved: @escaping () -> Void) {
        self.child = child; self.onSaved = onSaved
        _firstName = State(initialValue: child.firstName); _lastName = State(initialValue: child.lastName)
        _birthdate = State(initialValue: child.birthdate ?? Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Core identity") {
                    TextField("Legal first name", text: $firstName)
                    TextField("Legal last name", text: $lastName)
                    DatePicker("Birthdate", selection: $birthdate, in: ...Date(), displayedComponents: .date)
                }
                Text("Health, medication, and compliance values are completed through child assignments so their approved evidence remains attached.")
                    .font(.caption).foregroundColor(.secondary)
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("Child Identity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(isSaving) }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.updateChild(childId: child.id, firstName: firstName, lastName: lastName, birthdate: birthdate)
                await MainActor.run { isSaving = false; onSaved(); dismiss() }
            } catch {
                await MainActor.run { isSaving = false; errorMessage = AppErrorMessage.school("Could not update child identity", error) }
            }
        }
    }
}
