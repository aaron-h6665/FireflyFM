import SwiftUI

struct FamilyRequestsView: View {
    var focusRequestId: UUID? = nil
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var requests: [FamilyRequest] = []
    @State private var children: [Child] = []
    @State private var composing = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var displayedRequests: [FamilyRequest] {
        guard let focusRequestId else { return requests }
        return requests.filter { $0.id == focusRequestId }
    }
    private var childById: [UUID: Child] { Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) }) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppConstants.Colors.background.ignoresSafeArea()
            Group {
                if isLoading { ProgressView().tint(AppConstants.Colors.accessibleYellow) }
                else if displayedRequests.isEmpty {
                    ContentUnavailableView("No family requests", systemImage: "person.crop.circle.badge.questionmark", description: Text(emptyDescription))
                } else {
                    List(displayedRequests) { request in requestRow(request) }
                        .listStyle(.plain).scrollContentBackground(.hidden).refreshable { await load() }
                }
            }
            if appSession.role == .parent, children.isEmpty == false {
                Button { composing = true } label: {
                    Image(systemName: "plus").font(.title2.bold()).foregroundColor(AppConstants.Colors.brandNavy)
                        .frame(width: 58, height: 58).background(AppConstants.Colors.accessibleYellow).clipShape(Circle()).shadow(radius: 5)
                }.padding()
            }
        }
        .navigationTitle("Family Requests")
        .sheet(isPresented: $composing) { FamilyRequestComposer(children: children) { Task { await load() } } }
        .task(id: appSession.activeMembershipId) { await load() }
    }

    private var emptyDescription: String {
        appSession.role == .parent
            ? "Send an absence, pickup change, medication question, or general request to school staff."
            : "New parent requests for this school will appear here."
    }

    private func requestRow(_ request: FamilyRequest) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading) {
                    Text(childById[request.childId]?.fullName ?? "Child").font(.headline)
                    Text(request.requestType.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
                }
                Spacer(); Text(request.status.capitalized).font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
            }
            ForEach(request.details.keys.sorted(), id: \.self) { key in
                if let value = request.details[key]?.stringValue, !value.isEmpty {
                    Text(value).font(.subheadline).foregroundColor(AppConstants.Colors.primaryText)
                }
            }
            Text(request.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundColor(AppConstants.Colors.secondaryText)
            if appSession.role == .teacher || appSession.role == .schoolDirector {
                HStack {
                    Button("Acknowledge") { update(request, status: "acknowledged") }
                    Button("Complete") { update(request, status: "completed") }
                }.buttonStyle(.bordered).tint(AppConstants.Colors.accessibleYellow).font(.caption.bold())
            }
        }.padding(.vertical, 6).listRowBackground(AppConstants.Colors.card)
    }

    private func update(_ request: FamilyRequest, status: String) {
        Task {
            do { _ = try await SchoolOperationsService.shared.updateFamilyRequestStatus(requestId: request.id, status: status); await load() }
            catch { await MainActor.run { errorMessage = AppErrorMessage.school("Could not update request", error) } }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        do {
            if let schoolId = appSession.activeSchool?.id {
                async let loadedChildren = SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)
                async let loadedRequests = SchoolOperationsService.shared.fetchFamilyRequests(schoolId: schoolId, status: nil)
                children = try await loadedChildren; requests = try await loadedRequests
            }
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) { isLoading = false }
        catch { isLoading = false; errorMessage = AppErrorMessage.school("Could not load family requests", error) }
    }
}

private struct FamilyRequestComposer: View {
    @Environment(\.dismiss) private var dismiss
    let children: [Child]
    var onSaved: () -> Void
    @State private var childId: UUID?
    @State private var type = "general"
    @State private var details = ""
    @State private var effectiveAt = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Child", selection: $childId) {
                    Text("Select child").tag(Optional<UUID>.none)
                    ForEach(children) { Text($0.fullName).tag(Optional($0.id)) }
                }
                Picker("Request", selection: $type) {
                    Text("Absence").tag("absence")
                    Text("Pickup Change").tag("pickup_change")
                    Text("Medication Question").tag("medication")
                    Text("General").tag("general")
                }
                DatePicker("Effective", selection: $effectiveAt)
                TextField("What should the school know?", text: $details, axis: .vertical).lineLimit(3...7)
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("New Family Request")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Sending…" : "Send") { save() }
                        .disabled(childId == nil || details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear { childId = childId ?? children.first?.id }
        }
    }

    private func save() {
        guard let childId else { return }
        isSaving = true
        Task {
            do {
                _ = try await SchoolOperationsService.shared.submitFamilyRequest(
                    childId: childId, type: type,
                    details: ["message": .string(details), "effective_at": .string(ISO8601DateFormatter().string(from: effectiveAt))]
                )
                await MainActor.run { isSaving = false; onSaved(); dismiss() }
            } catch {
                await MainActor.run { isSaving = false; errorMessage = AppErrorMessage.school("Could not send request", error) }
            }
        }
    }
}
