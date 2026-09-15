import SDWebImageSwiftUI
import SwiftUI

struct ConversationsListView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var model = ChatRoomListModel()
    @State private var showingCreateChat = false
    @State private var createdHQRoom: ChatRoom?
    @State private var roomPendingLeave: ChatRoomListItem?

    private var accessPolicy: ChatAccessPolicy {
        ChatAccessPolicy(context: appSession.accessContext())
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            FireflyScreen {
                ZStack {
                    VStack(spacing: 0) {
                        header(searchText: $model.searchText)

                        if !model.pendingInvites.isEmpty {
                            pendingInvitesSection
                        }

                        if model.phase.isLoading {
                            Spacer()
                            ProgressView().tint(FireflyTheme.Colors.primaryAction)
                            Spacer()
                        } else if model.filteredRoomItems.isEmpty && model.pendingInvites.isEmpty {
                            Spacer()
                            FireflyEmptyState(
                                title: model.searchText.isEmpty ? "No chats yet" : "No chats found",
                                systemImage: "bubble.left.and.bubble.right.fill"
                            )
                            .padding(.horizontal)
                            Spacer()
                        } else {
                            roomList
                        }

                        if let message = model.mutationError {
                            FireflyInlineError(message: message)
                                .padding(.horizontal)
                        }
                        if case .failed(let message) = model.phase {
                            FireflyInlineError(message: message)
                                .padding(.horizontal)
                        }
                    }

                    if accessPolicy.canCreateAnyRoom {
                        floatingCreateButton
                    }
                }
            }
            .sheet(isPresented: $showingCreateChat) {
                if accessPolicy.canCreateHQRoom {
                    CreateHQChatRoomView { room in
                        createdHQRoom = room
                        Task { await model.load() }
                    }
                } else {
                    CreateChatRoomView {
                        Task { await model.load() }
                    }
                }
            }
            .navigationDestination(item: $createdHQRoom) { room in
                ChatRoomScreen(room: room) {
                    Task { await model.load() }
                }
            }
            .confirmationDialog(
                "Leave \(roomPendingLeave?.room.name ?? "this room")?",
                isPresented: Binding(
                    get: { roomPendingLeave != nil },
                    set: { if !$0 { roomPendingLeave = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Leave Room", role: .destructive) {
                    guard let item = roomPendingLeave else { return }
                    roomPendingLeave = nil
                    Task { await model.leave(item) }
                }
                Button("Cancel", role: .cancel) { roomPendingLeave = nil }
            } message: {
                Text("You will immediately lose access to this chat and its message history.")
            }
        }
        .task(id: appSession.activeMembershipId) {
            await model.start(
                schoolId: appSession.activeSchool?.id,
                includeAllSchoolRooms: accessPolicy.canOverseeSchoolRooms,
                membershipScope: appSession.activeSchool?.id.uuidString ?? "all"
            )
        }
        .onDisappear {
            Task { await model.stop() }
        }
    }

    private func header(searchText: Binding<String>) -> some View {
        VStack(spacing: FireflyTheme.Layout.spacingMedium) {
            HStack {
                Text("Messages")
                    .font(.largeTitle.bold())
                    .foregroundColor(FireflyTheme.Colors.primaryText)
                Spacer()
                if accessPolicy.canCreateAnyRoom {
                    Button {
                        showingCreateChat = true
                    } label: {
                        Image(systemName: "message.badge.plus")
                            .font(.title2)
                            .foregroundColor(FireflyTheme.Colors.primaryText)
                            .frame(
                                width: FireflyTheme.Layout.minimumTapTarget,
                                height: FireflyTheme.Layout.minimumTapTarget
                            )
                    }
                    .accessibilityLabel("Create chat")
                }
            }
            FireflySearchField(placeholder: "Search rooms", text: searchText)
        }
        .padding(.horizontal)
        .padding(.vertical, FireflyTheme.Layout.spacingSmall)
    }

    private var roomList: some View {
        List {
            ForEach(model.filteredRoomItems) { item in
                NavigationLink {
                    ChatRoomScreen(room: item.room) {
                        Task { await model.load() }
                    }
                } label: {
                    ChatRoomRow(item: item)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        Task { await model.toggleNotifications(item) }
                    } label: {
                        Label(
                            item.notificationsEnabled ? "Mute" : "Notify",
                            systemImage: item.notificationsEnabled ? "bell.slash.fill" : "bell.fill"
                        )
                    }
                    .tint(.orange)

                    Button {
                        Task { await model.markRead(item) }
                    } label: {
                        Label("Read", systemImage: "checkmark.circle.fill")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if accessPolicy.canLeave(room: item.room) {
                        Button(role: .destructive) {
                            roomPendingLeave = item
                        } label: {
                            Label("Leave", systemImage: "rectangle.portrait.and.arrow.right.fill")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
    }

    private var floatingCreateButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showingCreateChat = true
                } label: {
                    Image(systemName: "message.fill")
                        .font(.title.weight(.semibold))
                        .foregroundColor(FireflyTheme.Colors.brandNavy)
                        .frame(width: 60, height: 60)
                        .background(FireflyTheme.Colors.fireflyGlow)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .accessibilityLabel("Create chat")
                .padding(.trailing, FireflyTheme.Layout.spacingLarge)
                .padding(.bottom, FireflyTheme.Layout.spacingLarge)
            }
        }
    }

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.badge.fill")
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Text("Chat Invitations (\(model.pendingInvites.count))")
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
            }

            ForEach(model.pendingInvites) { invite in
                HStack(spacing: 12) {
                    Circle()
                        .fill(AppConstants.Colors.accessibleYellow.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: invite.room.isHQCustomRoom ? "building.2.crop.circle.fill" : "person.2.fill")
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(invite.room.name)
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .lineLimit(1)
                            if invite.room.isHQCustomRoom {
                                Text("HQ")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(AppConstants.Colors.accessibleYellow.opacity(0.2))
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                    .cornerRadius(4)
                            }
                        }
                        if let description = invite.room.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.secondaryText)
                                .lineLimit(1)
                        } else {
                            Text("You have been invited to join this conversation.")
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.secondaryText)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            Task { await model.respondToInvite(invite, accept: true) }
                        } label: {
                            Text("Accept")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.brandNavy)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppConstants.Colors.accessibleYellow)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await model.respondToInvite(invite, accept: false) }
                        } label: {
                            Text("Decline")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(AppConstants.Colors.card)
                .cornerRadius(10)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct ChatRoomRow: View {
    let item: ChatRoomListItem

    var body: some View {
        HStack(spacing: 14) {
            roomAvatar

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.room.name)
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .lineLimit(1)

                    if item.room.isHQCustomRoom {
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                    }

                    if item.notificationsEnabled == false {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
                    }

                    if item.room.isReadOnly {
                        Image(systemName: "archivebox.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Text(previewText)
                    .font(.subheadline)
                    .foregroundColor(
                        item.unreadCount > 0
                            ? AppConstants.Colors.primaryText.opacity(0.9)
                            : AppConstants.Colors.secondaryText
                    )
                    .fontWeight(item.unreadCount > 0 ? .semibold : .regular)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(timeAgo(from: item.lastActivityAt))
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.5))

                if item.unreadCount > 0 {
                    Text(item.unreadCount > 99 ? "99+" : "\(item.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundColor(AppConstants.Colors.brandNavy)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, item.unreadCount > 9 ? 5 : 0)
                        .background(AppConstants.Colors.accessibleYellow)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var roomAvatar: some View {
        if let profileUrl = item.room.profileImageUrl, let url = URL(string: profileUrl) {
            WebImage(url: url)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(avatarColor.opacity(0.22))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: avatarSymbol)
                        .font(.headline)
                        .foregroundColor(avatarColor)
                )
        }
    }

    private var avatarSymbol: String {
        if item.room.isHQCustomRoom { return "building.2.crop.circle.fill" }
        if item.room.isChildFamilyRoom { return "person.2.fill" }
        if item.room.isSchoolCommunityRoom { return "building.2.fill" }
        return "bubble.left.and.bubble.right.fill"
    }

    private var avatarColor: Color {
        if item.room.isHQCustomRoom { return AppConstants.Colors.accessibleYellow }
        return item.room.isChildFamilyRoom ? AppConstants.Colors.accessibleYellow : .blue
    }

    private var previewText: String {
        ChatMessagePresentation.preview(for: item)
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
