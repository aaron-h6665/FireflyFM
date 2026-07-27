//
//  ChatViewWrapper.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI
import SDWebImageSwiftUI

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
                    NavigationStack {
                        CareTodayView(initialChildId: room.subjectChildId, opensComposer: true)
                    }
                case .familyRequest:
                    NavigationStack {
                        FamilyRequestsView(initialChildId: room.subjectChildId, opensComposer: true)
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
