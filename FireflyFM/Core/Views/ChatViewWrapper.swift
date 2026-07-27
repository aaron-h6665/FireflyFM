//
//  ChatViewWrapper.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI
import SDWebImageSwiftUI
import Supabase
import PostgREST

enum ChatRoomAction: String, Identifiable {
    case everydayCare
    case familyRequest
    case callGuardians

    var id: String { rawValue }
}

struct ChatRoomScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var room: ChatRoom
    @State private var searchTrigger = 0
    @State private var showingSettings = false
    @State private var memberCount = 0
    @State private var activeAction: ChatRoomAction?

    var onRoomChanged: () -> Void

    init(room: ChatRoom, onRoomChanged: @escaping () -> Void = {}) {
        _room = State(initialValue: room)
        self.onRoomChanged = onRoomChanged
    }

    var body: some View {
        ChatViewWrapper(
            room: room,
            role: appSession.role,
            searchTrigger: searchTrigger,
            onAction: { activeAction = $0 }
        )
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackground(AppConstants.Colors.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        showingSettings = true
                    } label: {
                        HStack(spacing: 12) {
                            roomAvatar(size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(room.name).font(.headline).lineLimit(1)
                                Text("\(memberCount) members").font(.caption2).foregroundColor(AppConstants.Colors.secondaryText)
                            }
                            .foregroundColor(AppConstants.Colors.primaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View \(room.name) details and members")
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        searchTrigger += 1
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(AppConstants.Colors.primaryText)

                    if appSession.role == .schoolDirector {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(AppConstants.Colors.primaryText)
                    } else {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(AppConstants.Colors.primaryText)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ChatRoomSettingsView(
                    room: room,
                    onRoomUpdated: { updatedRoom in
                        room = updatedRoom
                        onRoomChanged()
                    },
                    onRoomClosed: {
                        showingSettings = false
                        onRoomChanged()
                        dismiss()
                    }
                )
            }
            .sheet(item: $activeAction) { action in
                switch action {
                case .everydayCare:
                    if let childId = room.subjectChildId {
                        ChatDailyActivityComposerView(childId: childId, roomId: room.id)
                    } else {
                        ContentUnavailableView("No linked child", systemImage: "heart.slash.fill")
                    }
                case .familyRequest:
                    if let childId = room.subjectChildId {
                        ChatFamilyRequestComposerView(childId: childId)
                    } else {
                        ContentUnavailableView("No linked child", systemImage: "person.crop.circle.badge.exclamationmark")
                    }
                case .callGuardians:
                    if let childId = room.subjectChildId {
                        CallGuardiansView(childId: childId)
                    } else {
                        ContentUnavailableView("No linked child", systemImage: "phone.down.fill")
                    }
                }
            }
            .task {
                memberCount = (try? await ChatService.shared.fetchParticipants(roomId: room.id).count) ?? 0
            }
    }

    @ViewBuilder
    private func roomAvatar(size: CGFloat) -> some View {
        if let profileUrl = room.profileImageUrl, let url = URL(string: profileUrl) {
            WebImage(url: url)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(room.name.prefix(1)).uppercased())
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                )
        }
    }
}

struct ChatViewWrapper: UIViewControllerRepresentable {
    let room: ChatRoom
    let role: SchoolRole?
    let searchTrigger: Int
    let onAction: (ChatRoomAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(searchTrigger: searchTrigger)
    }

    func makeUIViewController(context: Context) -> ChatViewManager {
        let chatManager = ChatViewManager()
        chatManager.room = room
        chatManager.role = role
        chatManager.onAction = onAction
        return chatManager
    }

    func updateUIViewController(_ uiViewController: ChatViewManager, context: Context) {
        uiViewController.room = room
        uiViewController.role = role
        uiViewController.onAction = onAction
        uiViewController.updateRoomState()

        if context.coordinator.lastSearchTrigger != searchTrigger {
            context.coordinator.lastSearchTrigger = searchTrigger
            uiViewController.presentMessageSearch()
        }
    }

    final class Coordinator {
        var lastSearchTrigger: Int

        init(searchTrigger: Int) {
            self.lastSearchTrigger = searchTrigger
        }
    }
}

private struct CallGuardiansView: View {
    @Environment(\.dismiss) private var dismiss
    let childId: UUID

    @State private var contacts: [ChildEmergencyContact] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if contacts.filter({ $0.phone?.isEmpty == false }).isEmpty {
                    ContentUnavailableView(
                        "No callable guardians",
                        systemImage: "phone.down.fill",
                        description: Text("Add a verified emergency contact phone number to the child profile first.")
                    )
                } else {
                    List(contacts.filter { $0.phone?.isEmpty == false }) { contact in
                        Button {
                            call(contact)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "phone.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name).foregroundColor(AppConstants.Colors.primaryText)
                                    Text([contact.relationship, contact.phone].compactMap { $0 }.joined(separator: " • "))
                                        .font(.caption)
                                        .foregroundColor(AppConstants.Colors.secondaryText)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppConstants.Colors.background)
            .navigationTitle("Call Guardians")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .alert("Could not load contacts", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            contacts = try await SchoolWorkflowService.shared.fetchChildEmergencyContacts(childId: childId)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = AppErrorMessage.school("Could not load guardian contacts", error)
        }
    }

    private func call(_ contact: ChildEmergencyContact) {
        guard let phone = contact.phone else { return }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel:\(digits)") else { return }
        UIApplication.shared.open(url)
    }
}

struct ChatStructuredEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let sourceType: String
    let sourceId: UUID
    let role: SchoolRole?

    @State private var careEvent: ChildCareEvent?
    @State private var familyRequest: FamilyRequest?
    @State private var isLoading = true
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                Group {
                    if isLoading {
                        ProgressView("Opening update")
                    } else if let careEvent {
                        careDetail(careEvent)
                    } else if let familyRequest {
                        requestDetail(familyRequest)
                    } else {
                        ContentUnavailableView(
                            "Update unavailable",
                            systemImage: "exclamationmark.bubble.fill",
                            description: Text(errorMessage ?? "This update may no longer be available.")
                        )
                    }
                }
            }
            .navigationTitle(sourceType == "child_care_events" ? "Daily Activity" : "Family Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func careDetail(_ event: ChildCareEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(title: event.eventType.title, symbol: event.eventType.symbol, date: event.occurredAt)
                detailValues(event.details, excluding: ["photo_path"])
                if event.visibility == "staff_only" {
                    Label("Staff Only", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
            }
            .padding()
        }
    }

    private func requestDetail(_ request: FamilyRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(
                    title: request.requestType.replacingOccurrences(of: "_", with: " ").capitalized,
                    symbol: "person.crop.circle.badge.questionmark",
                    date: request.createdAt
                )
                Text(request.status.capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppConstants.Colors.wingMist)
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .clipShape(Capsule())
                detailValues(request.details)

                if role == .teacher || role == .schoolDirector {
                    HStack {
                        Button("Acknowledge") { updateRequest(request, status: "acknowledged") }
                            .buttonStyle(.bordered)
                        Button("Complete") { updateRequest(request, status: "completed") }
                            .buttonStyle(.borderedProminent)
                    }
                    .tint(AppConstants.Colors.primaryAction)
                    .disabled(isUpdating)
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
            }
            .padding()
        }
    }

    private func detailHeader(title: String, symbol: String, date: Date) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.brandNavy)
                .frame(width: 50, height: 50)
                .background(AppConstants.Colors.fireflyGlow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold()).foregroundColor(AppConstants.Colors.primaryText)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
        }
    }

    private func detailValues(_ values: [String: FireflyJSONValue], excluding excluded: Set<String> = []) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(values.keys.sorted().filter { !excluded.contains($0) }, id: \.self) { key in
                if let value = values[key]?.stringValue, !value.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.secondaryText)
                        Text(value).foregroundColor(AppConstants.Colors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            if sourceType == "child_care_events" {
                let rows: [ChildCareEvent] = try await AppConstants.supabase.from("child_care_events")
                    .select().eq("id", value: sourceId).limit(1).execute().value
                careEvent = rows.first
            } else if sourceType == "family_requests" {
                let rows: [FamilyRequest] = try await AppConstants.supabase.from("family_requests")
                    .select().eq("id", value: sourceId).limit(1).execute().value
                familyRequest = rows.first
            }
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = AppErrorMessage.school("Could not open this update", error)
        }
    }

    private func updateRequest(_ request: FamilyRequest, status: String) {
        isUpdating = true
        Task {
            do {
                familyRequest = try await SchoolOperationsService.shared.updateFamilyRequestStatus(
                    requestId: request.id,
                    status: status
                )
                isUpdating = false
            } catch {
                isUpdating = false
                errorMessage = AppErrorMessage.school("Could not update the request", error)
            }
        }
    }
}
